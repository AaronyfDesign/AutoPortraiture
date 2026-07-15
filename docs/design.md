# AutoPortraiture 设计文档

## 背景

本项目经历了以下阶段的演进：

1. **LR SDK Lua 插件**（已弃用）：通过 Lightroom SDK 插件实现全流程，开发中发现 LR SDK 限制较多，调试周期长，跨版本兼容性脆弱。
2. **LR 导出操作 Shell 脚本**（当前版本）：利用 LR 内置的导出操作功能，在导出 JPEG 后自动调用 Photoshop 执行磨皮。通过 `app.doAction()` 回放预录的 PS Action 调用 Portraiture 滤镜。

期间曾尝试用 `executeAction(stringIDToTypeID(...))` 直接按标识符调用滤镜（绕过预录 Action），但第三方滤镜的 string ID 难以查询、且部分滤镜需通过对话框确认才能载入效果，最终回到 `doAction` 方案——录制简单、兼容性好、Portraiture 的参数直接锁定在 Action 中。

## 方案概述

利用 Lightroom 的导出操作（Export Action）功能，在 LR 导出 JPEG 后自动调用 Shell 脚本，脚本通过 AppleScript 桥接 Photoshop 执行 JSX 脚本，回放预录的 Action 完成磨皮和文件保存。

工作流程：

```
Lightroom 导出 JPEG          Shell 脚本                        Photoshop JSX
┌─────────────┐     ┌──────────────────────────┐     ┌──────────────────────────┐
│  选中照片    │     │  接收文件路径 $1        │     │  打开 JPEG               │
│  导出为      │────▶│  生成 JSX（内嵌路径）   │────▶│  复制背景图层            │
│  JPEG       │     │  生成 AppleScript .scpt │     │  app.doAction 回放 Action │
│  到 Export  │     │  osascript 执行         │     │  合并图层                │
│  Actions    │     │  检查输出 → 删除原文件  │     │  另存为 _processed.jpg   │
└─────────────┘     │  清理临时文件           │     │  关闭文档                │
                    │  发 macOS 通知          │     └──────────────────────────┘
                    └──────────────────────────┘
```

## 滤镜调用方式

### 当前方式：app.doAction()

```javascript
app.doAction(actionName, actionSet);
```

回放预录的 Photoshop Action，Action 中包含完整的 Portraiture 滤镜步骤及参数设置。需要在 PS 中预先录制：

1. 打开照片，窗口 → 动作，新建 Action Set `AutoPortraiture`
2. 新建 Action `Portraiture`，开始录制
3. 滤镜 → Imagenomic → Portraiture 3/4，调整参数，确定
4. 停止录制

### 为什么选择 doAction

| 维度 | `app.doAction()` | `executeAction()` |
| --- | --- | --- |
| 依赖 | 需预录 Action | 不需要预录 |
| 参数 | 录制时锁定 | 需通过 ActionDescriptor 传参 |
| 第三方滤镜兼容性 | 好（录制什么回放什么） | 需查询 string ID，部分滤镜无法静默调用 |
| 对话框处理 | Action 回放时按录制设置执行 | 需额外处理滤镜对话框阻塞 |
| 用户体验 | 需录制一次 | 零配置但兼容性不可控 |

曾尝试用 `executeAction` 直接调用滤镜（Camera Raw、Twirl 等内置滤镜可成功），但第三方滤镜如 Portraiture 的 string ID 难以查询，且部分滤镜必须通过对话框确认才能载入效果，`DialogModes.NO` 静默调用不生效。`doAction` 方案通过录制完整的滤镜交互过程，回放时自动复现，兼容性最好。

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

1. CONFIG 区：配置 Action 名称、Set 名称、JPEG 质量
2. 输入验证：检查参数和文件存在性
3. 生成 JSX：通过 heredoc 将路径和配置内嵌到 JSX 代码中
4. 生成 AppleScript .scpt：通过 Python 写入文件（处理 `«class utf8»` 特殊字符）
5. 执行 osascript 调用 Photoshop
6. 检查输出文件，记录成功/失败
7. 删除原始 JPEG 和临时 PSD
8. 清理临时 JSX 和 .scpt 文件
9. macOS 通知

关键技术决策：

- **Python 生成 .scpt 文件**：AppleScript 中 `«class utf8»` 的 `«»` 字符无法在 `osascript -e` 单行参数中使用，必须写入 `.scpt` 文件。Python 对 Unicode 处理可靠。
- **app.displayDialogs = DialogModes.NO**：在 JSX 开头设置，抑制 PS 自身的对话框（如颜色模式转换提示）。Action 内的滤镜步骤按录制时的设置执行，不受此设置影响。
- **try-catch 包裹 doAction**：Action 不存在或执行失败时不会中断整个流程，照片仍会被保存（但未经滤镜处理）。

### JSX 脚本（内嵌在 Shell heredoc 中）

步骤：

1. 设置 `app.displayDialogs = DialogModes.NO`
2. 打开 JPEG 文件
3. 复制背景图层（非破坏性编辑）
4. `app.doAction(actionName, actionSet)` 回放 Action 调用 Portraiture
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

**Action 未录制或名称不匹配**：如果 `ACTION_NAME`/`ACTION_SET` 与 PS 中实际录制的 Action 不一致，`app.doAction()` 会抛异常，被 try-catch 捕获。照片仍会被保存但未经滤镜处理。日志中会有 "Action failed" 记录。

**Portraiture 未安装**：如果目标机器未安装 Portraiture 插件，录制 Action 时 Portraiture 步骤不会生效，回放时也不会执行滤镜。需确保 Portraiture 已正确安装。

**Photoshop 版本路径**：AppleScript 中硬编码了 `Adobe Photoshop 2025`，更换 PS 版本需修改脚本。

**AppleScript 权限**：首次运行时 macOS 可能弹出 AppleScript 自动化权限对话框，需要用户授权 `do javascript` 权限。

## 与原 LR 插件方案的对比

| 维度 | LR 插件方案 | 导出操作方案 |
| --- | --- | --- |
| 依赖 | 需开发 Lua 插件，受 SDK 限制 | 仅需 shell + Photoshop |
| 安装 | 复制 .lrplugin 到 Modules 目录 | 复制 .sh 到 Export Actions |
| 滤镜调用 | JSX + executeAction | JSX + app.doAction |
| 预录 Action | 不需要 | 需要（录制一次） |
| 调试 | Plugin Manager Reload，LrLogger | 终端直接运行，日志文件 |
| 自动回传 LR | 支持（SDK API） | 不支持（手动导入） |
| 维护成本 | 高 | 低 |
