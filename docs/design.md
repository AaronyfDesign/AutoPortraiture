# AutoPortraiture 设计文档

## 背景

本项目经历了三个阶段的演进：

1. **LR SDK Lua 插件**（已弃用）：通过 Lightroom SDK 插件实现全流程，开发中发现 LR SDK 限制较多，调试周期长，跨版本兼容性脆弱。
2. **LR 导出操作 Shell 脚本**（初始版本）：利用 LR 内置的导出操作功能，在导出 JPEG 后自动调用 Photoshop 执行磨皮。通过 `app.doAction()` 回放预录的 PS Action。
3. **直接滤镜调用**（当前版本）：将滤镜调用方式从 `app.doAction()` 改为 `executeAction(stringIDToTypeID(FILTER_ID), ...)`，不再依赖预录 Action，滤镜标识符可配置。JSX 内部含 charID 回退逻辑。已通过 Camera Raw 和 Twirl 滤镜实测验证。

## 方案概述

利用 Lightroom 的导出操作（Export Action）功能，在 LR 导出 JPEG 后自动调用 Shell 脚本，脚本通过 AppleScript 桥接 Photoshop 执行 JSX 脚本，完成滤镜调用和文件保存。

工作流程：

```
Lightroom 导出 JPEG          Shell 脚本                        Photoshop JSX
┌─────────────┐     ┌──────────────────────────┐     ┌──────────────────────────┐
│  选中照片    │     │  接收文件路径 $1        │     │  打开 JPEG               │
│  导出为      │────▶│  生成 JSX（内嵌路径）   │────▶│  复制背景图层            │
│  JPEG       │     │  生成 AppleScript .scpt │     │  executeAction 调用滤镜  │
│  到 Export  │     │  osascript 执行         │     │  合并图层                │
│  Actions    │     │  检查输出 → 删除原文件  │     │  另存为 _processed.jpg   │
└─────────────┘     │  清理临时文件           │     │  关闭文档                │
                    │  发 macOS 通知          │     └──────────────────────────┘
                    └──────────────────────────┘
```

## 滤镜调用方式

### 当前方式：executeAction + stringIDToTypeID（含 charID 回退）

```javascript
var filterDesc = new ActionDescriptor();
try {
    executeAction(stringIDToTypeID(filterId), filterDesc, dialogMode);
    $.writeln("Filter applied (stringID): " + filterId);
} catch (e1) {
    // 回退：尝试 4 字符 charID
    executeAction(charIDToTypeID(filterId), filterDesc, dialogMode);
    $.writeln("Filter applied (charID): " + filterId);
}
```

JSX 内部先尝试 stringID 调用，失败后自动回退到 charID（4 字符代码），兼容只注册了 charID 的老滤镜。`filterId` 是 Photoshop 内部注册的标识符，对应滤镜在 Filter 菜单中的条目。常用值：

| 滤镜 | FILTER_ID | 测试状态 |
| --- | --- | --- |
| Camera Raw Filter | `AdobeCameraRawFilter` | ✓ 通过 |
| Twirl (旋转扭曲) | `twirl` | ✓ 通过 |
| Gaussian Blur | `GaussianBlur` | 理论可用 |
| Surface Blur | `surfaceBlur` | 理论可用 |
| Smart Sharpen | `smartSharpen` | 理论可用 |

第三方滤镜（如 Portraiture）安装后会注册自己的 string ID，可通过 Adobe ScriptingListener 插件查询。

### 与 doAction 方式的对比

| 维度 | `app.doAction()` | `executeAction()` |
| --- | --- | --- |
| 依赖 | 需在 PS 中预录 Action | 不需要预录 |
| 参数 | 录制时锁定 | 可通过 ActionDescriptor 传参 |
| 切换滤镜 | 需重新录制 Action | 改 FILTER_ID 配置项即可 |
| 可移植性 | 绑定到特定 PS 的 Action 配置 | 只需目标机器安装了对应滤镜 |
| 用户体验 | 额外的录制步骤 | 零配置，开箱即用 |

### 查询第三方滤镜 string ID 的方法

1. 启用 Photoshop 的 ScriptingListener 插件
2. 在 PS 中手动运行目标滤镜
3. 打开 `~/Desktop/ScriptingListenerJS.log`
4. 找到对应的 `executeAction(stringIDToTypeID("xxx"), ...)` 调用
5. 复制 string ID 到脚本的 FILTER_ID 配置项

## 目录结构

```
AutoPortraiture/
├── scripts/
│   └── AutoPortraiture.sh          # 主脚本
├── docs/
│   ├── usage.md                    # 使用指南
│   ├── design.md                   # 本文档
│   └── troubleshooting.md          # LR SDK 阶段排错记录（历史参考）
├── AutoPortraiture.lrplugin/        # 已弃用：LR SDK Lua 插件
└── README.md
```

## 核心组件

### AutoPortraiture.sh — 主脚本

职责：接收 LR 导出的文件路径，生成 JSX，通过 AppleScript 调用 Photoshop 执行，处理输出和清理。

脚本结构：

1. CONFIG 区：配置滤镜标识符、对话框模式、自动点击 OK、JPEG 质量
2. 输入验证：检查参数和文件存在性
3. 生成 JSX：通过 heredoc 将路径和配置内嵌到 JSX 代码中
4. 生成 AppleScript .scpt：通过 Python 写入文件（处理 `«class utf8»` 特殊字符）
5. 启动后台自动点击进程（当 AUTO_CLICK_OK=yes 时）
6. 执行 osascript 调用 Photoshop
7. 清理后台自动点击进程
8. 检查输出文件，记录成功/失败
9. 删除原始 JPEG 和临时 PSD
10. 清理临时 JSX 和 .scpt 文件
11. macOS 通知

关键技术决策：

- **Python 生成 .scpt 文件**：AppleScript 中 `«class utf8»` 的 `«»` 字符无法在 `osascript -e` 单行参数中使用，必须写入 `.scpt` 文件。Python 的 `print()` 对 Unicode 处理可靠。
- **app.displayDialogs = DialogModes.NO**：在 JSX 开头设置，抑制 PS 自身的对话框（如颜色模式转换提示）。滤镜的对话框由 `executeAction` 的第三个参数单独控制。
- **try-catch 包裹滤镜调用**：滤镜标识符错误时不会中断整个流程，照片仍会被保存（但未经滤镜处理）。
- **后台自动点击 OK**：当 FILTER_DIALOG_MODE=ALL 且 AUTO_CLICK_OK=yes 时，在调 Photoshop 之前启动一个后台子进程，用 System Events 每 0.5 秒轮询 Photoshop 窗口，检测到滤镜对话框后自动点击 OK 按钮（先试 "OK"，再试 "确定"）。这使得 Twirl、Portraiture 等需点击确认才能载入效果的滤镜可以全自动执行，JSX 被 executeAction 阻塞时后台进程并行运行，点击 OK 后阻塞解除，流程继续。

### JSX 脚本（内嵌在 Shell heredoc 中）

步骤：

1. 设置 `app.displayDialogs = DialogModes.NO`
2. 打开 JPEG 文件
3. 复制背景图层（非破坏性编辑）
4. `executeAction(stringIDToTypeID(FILTER_ID), desc, dialogMode)` 调用滤镜（DialogModes.ALL 时弹出对话框，后台进程自动点击 OK）
5. `doc.flatten()` 合并图层
6. `doc.saveAs(outFile, JPEGSaveOptions, true, Extension.LOWERCASE)` 另存为
7. `doc.close(SaveOptions.DONOTSAVECHANGES)` 关闭文档
8. 恢复 `app.displayDialogs = DialogModes.ALL`

### AppleScript 桥接

```applescript
tell application "Adobe Photoshop 2025"
  activate
  set jsCode to (read POSIX file "/tmp/ap_portraiture_xxx.jsx" as «class utf8»)
  do javascript jsCode
end tell
```

`«class utf8»` 确保 JSX 文件以 UTF-8 编码读取，支持中文路径。

## 风险与缓解

**滤镜标识符错误**：如果 FILTER_ID 配置错误，`executeAction` 会抛异常，被 try-catch 捕获。照片仍会被保存但未经滤镜处理。日志中会有 "Filter failed" 记录。

**Photoshop 版本路径**：AppleScript 中硬编码了 `Adobe Photoshop 2025`，更换 PS 版本需修改脚本。

**滤镜对话框阻塞**：当 `FILTER_DIALOG_MODE="ALL"` 时，`executeAction` 会弹出滤镜对话框并阻塞 JSX 执行。脚本通过后台进程用 System Events 自动点击 OK 解决此问题（已通过 Twirl 滤镜实测）。如果目标滤镜不支持静默执行（`DialogModes.NO`），则必须用 `ALL` + 自动点击模式。

**自动点击的辅助功能权限**：后台自动点击依赖 macOS Accessibility 权限。首次运行时需在「系统设置 → 隐私与安全 → 辅助功能」中为终端应用授权。未授权时自动点击静默失败，滤镜对话框会一直等待手动点击。

**AppleScript 权限**：首次运行时 macOS 可能弹出 AppleScript 权限对话框，需要用户授权。包括 `do javascript` 的自动化权限和自动点击的辅助功能权限。

## 与原 LR 插件方案的对比

| 维度 | LR 插件方案 | 导出操作方案 |
| --- | --- | --- |
| 依赖 | 需开发 Lua 插件，受 SDK 限制 | 仅需 shell + Photoshop |
| 安装 | 复制 .lrplugin 到 Modules 目录 | 复制 .sh 到 Export Actions |
| 滤镜调用 | JSX + executeAction | JSX + executeAction |
| 预录 Action | 不需要 | 不需要 |
| 调试 | Plugin Manager Reload，LrLogger | 终端直接运行，日志文件 |
| 自动回传 LR | 支持（SDK API） | 不支持（手动导入） |
| 维护成本 | 高 | 低 |
