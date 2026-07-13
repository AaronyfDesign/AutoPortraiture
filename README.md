# AutoPortraiture

> 一键磨皮工作流：Lightroom 导出 → Photoshop + Portraiture → 自动保存成品。

## 项目概述

AutoPortraiture 利用 Lightroom Classic 的 Export Action 功能，在导出照片后自动调用 Photoshop 执行 Imagenomic Portraiture 磨皮处理，将结果以 `<原文件名>_processed.jpg` 保存，并自动清理原始导出文件和临时 PSD。

整个流程无需手动操作 Photoshop，适合批量处理人像照片。

## 仓库结构

```
AutoPortraiture/
├── scripts/
│   └── AutoPortraiture.sh              # Export Action 脚本（核心）
├── AutoPortraiture.lrplugin/           # LR SDK 插件（已弃用，保留作参考）
│   ├── Info.lua
│   ├── main.lua
│   ├── PluginInit.lua
│   ├── PostProcess.lua
│   ├── PortraitureAction.jsx
│   └── Resources/
│       └── strings_en.lua
├── docs/
│   ├── design.md                       # 方案设计文档
│   └── troubleshooting.md             # LR SDK 插件问题排查记录
├── README.md
├── LICENSE
└── .gitignore
```

## 工作流程

```
Lightroom                          AutoPortraiture.sh              最终结果
┌───────────────┐                ┌─────────────────────────┐     ┌──────────────┐
│  选中照片      │                │  1. 接收 JPEG 路径 ($1)  │     │ photo_       │
│  导出 JPEG    │──JPEG 路径──▶  │  2. 生成 JSX（内嵌路径）│     │ processed    │
│  100% 质量    │                │  3. AppleScript 调 PS   │────▶│ .jpg         │
│  后处理选择   │                │  4. PS: 打开→磨皮→另存  │     │              │
│  AutoPortrait │                │  5. 删除原始 JPEG + PSD │     │ (原始 JPEG   │
│  -ure.sh      │                └─────────────────────────┘     │  已删除)     │
└───────────────┘                                                 └──────────────┘
```

## 前置要求

- macOS（当前仅支持 macOS，Windows 需自行适配 AppleScript 部分）
- Lightroom Classic（已测试 14.5.2）
- Adobe Photoshop（已测试 Photoshop 2025）
- Imagenomic Portraiture 插件（安装在 Photoshop 中）

## 安装

### 第一步：安装脚本

将 `AutoPortraiture.sh` 复制到 Lightroom 的 Export Actions 目录：

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
chmod +x ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/AutoPortraiture.sh
```

该目录是 Lightroom 专用目录，放在这里的可执行文件会自动出现在 LR 导出对话框的"后处理"下拉菜单中。

### 第二步：在 Photoshop 中录制 Portraiture Action

脚本通过 `app.doAction()` 回放 PS Action 来调用 Portraiture，需要预先录制：

1. 打开 Photoshop，进入 窗口 → 动作（Actions）
2. 点击新建动作组，命名为 `AutoPortraiture`
3. 在该组下新建动作，命名为 `Portraiture`
4. 开始录制：滤镜 → Imagenomic → Portraiture 3/4
5. 在 Portraiture 界面中调整磨皮参数，点击确定
6. 停止录制

录制完成后，脚本就能自动回放这个 Action，无需每次手动调参。

### 第三步：在 Lightroom 中配置导出

在 Lightroom 中选中照片，按导出（Cmd+Shift+E），设置：

- 图像格式：JPEG
- 质量：100%
- 后处理（Post-Processing）：选择 `AutoPortraiture.sh`

点击导出即可。LR 导出 JPEG 后会自动调用脚本，Photoshop 在后台完成磨皮和保存，处理完成后会收到 macOS 通知。

## 配置参数

编辑 `AutoPortraiture.sh` 顶部的 CONFIG 区域自定义行为：

```bash
# Photoshop Action 名称和 Action Set 名称
ACTION_NAME="Portraiture"
ACTION_SET="AutoPortraiture"

# 输出 JPEG 质量 (1-12, 12 = 最高)
JPEG_QUALITY=12
```

修改后同步到 Export Actions 目录：

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
```

## 脚本工作原理

`AutoPortraiture.sh` 完成以下步骤：

1. 接收 LR 传入的导出文件路径（`$1`）
2. 生成临时 JSX 脚本（将文件路径和配置参数内嵌其中）
3. 生成临时 AppleScript 文件（多行语法需要文件，不能用 `-e` 单行参数）
4. 通过 `osascript` 调用 Photoshop 执行 JSX：
   - 禁用所有 PS 对话框（`DialogModes.NO`）
   - 打开 JPEG 文件
   - 复制背景图层（非破坏性）
   - 调用 `app.doAction()` 回放 Portraiture Action
   - 合并图层
   - 另存为 `<原文件名>_processed.jpg`（JPEG 最高质量）
   - 关闭文档
   - 恢复 PS 对话框设置
5. 删除原始 JPEG
6. 删除临时 PSD 文件（如有）
7. 弹出 macOS 通知提示完成
8. 清理临时脚本文件

日志写入 `~/Desktop/autoportraiture.log`。

## 批量处理

在 Lightroom 中选中多张照片后导出，LR 会逐张导出 JPEG 并为每张调用一次脚本。Photoshop 会依次处理每张照片。如果需要更高效的批量处理（单次 PS 启动处理多张），可修改脚本收集所有路径后一次性传给 JSX 循环处理。

## 日志与排错

日志文件：`~/Desktop/autoportraiture.log`

常见问题：

- PS 未弹出但日志显示成功：脚本禁用了所有 PS 对话框，Photoshop 在后台处理。处理完成后会收到 macOS 通知。
- Action not available 错误：确认已在 PS 中录制了正确命名的 Action（`AutoPortraiture` 组下的 `Portraiture` 动作）。
- 输出文件未生成：检查日志中的 Photoshop 错误信息，确认 PS 已安装且能正常启动。

## 关于 LR SDK 插件（已弃用）

项目最初采用 Lightroom SDK 插件方案（`AutoPortraiture.lrplugin/` 目录），通过 Lua 代码实现全流程自动化。实际开发中发现 LR SDK 限制较多：异步 API 调用链复杂、模块加载机制严格、跨版本兼容性脆弱。最终改为 Export Action 方案，更简单可靠。

LR SDK 插件的代码保留在 `AutoPortraiture.lrplugin/` 目录中作参考，问题排查记录见 `docs/troubleshooting.md`。如需了解 LR SDK 的技术细节和踩坑经验，可参考该文档。

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
