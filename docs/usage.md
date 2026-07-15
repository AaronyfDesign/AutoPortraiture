# AutoPortraiture 使用指南

## 环境要求

- macOS
- Lightroom Classic（已测试 14.5.2）
- Adobe Photoshop（已测试 2025）
- 滤镜插件：如 Imagenomic Portraiture，需安装在 Photoshop 中

## 安装

### 1. 安装脚本

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
chmod +x ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/AutoPortraiture.sh
```

### 2. 在 Photoshop 中录制 Action

脚本通过 `app.doAction(actionName, actionSet)` 回放预录的 PS Action，需要先在 PS 中录制一个包含 Portraiture 步骤的 Action：

1. 打开 Photoshop，打开任意一张照片
2. 窗口 → 动作（Window → Actions），调出动作面板
3. 点击面板菜单 → 新建动作集（Action Set），命名为 `AutoPortraiture`
4. 在该集下新建动作（Action），命名为 `Portraiture`，点击「开始记录」
5. 滤镜 → Imagenomic → Portraiture 3/4
6. 在 Portraiture 界面中调整参数，点击确定
7. 回到动作面板，点击「停止录制」按钮

确保 Action 名称是 `Portraiture`，Action Set 名称是 `AutoPortraiture`，与脚本 CONFIG 中的配置一致。

### 3. 在 Lightroom 中配置导出

在 Lightroom 中选中照片，按 `Cmd + Shift + E` 打开导出对话框：

1. 图像格式：JPEG
2. 质量：100%
3. 向下滚动到"导出后"（Post-Processing）下拉菜单
4. 选择 `AutoPortraiture.sh`
5. 点击导出

导出完成后，脚本自动运行：Photoshop 打开 JPEG → 回放 Action 调用 Portraiture → 另存为 `<原文件名>_processed.jpg` → 删除原始 JPEG → 清理临时文件 → 弹出 macOS 通知。

## 配置参数

编辑 `scripts/AutoPortraiture.sh` 顶部 CONFIG 区域：

```bash
# Action 名称和 Action Set 名称（需与 PS 中录制的一致）
ACTION_NAME="Portraiture"
ACTION_SET="AutoPortraiture"

# 输出 JPEG 质量 (1-12, 12 = 最高)
JPEG_QUALITY=12
```

修改后同步到 Export Actions 目录：

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
```

如果使用了不同的 Action 名称或 Set 名称，修改 `ACTION_NAME` 和 `ACTION_SET` 即可。

## 批量处理

在 Lightroom 中选中多张照片后导出，LR 会逐张导出 JPEG 并为每张调用一次脚本。Photoshop 依次处理每张照片，全程无需手动干预。处理完成后每张照片都会收到 macOS 通知。

## 输出说明

每张照片处理完成后：

- 生成 `<原文件名>_processed.jpg`（与导出目录相同位置）
- 原始 JPEG（LR 导出的）被删除
- 临时 PSD 文件（如有）被删除
- 最终只保留 `_processed.jpg` 一个文件

## 日志

日志文件路径：`~/Desktop/autoportraiture.log`

每条记录包含时间戳和操作状态，可用于排错。示例：

```
2026-07-14 02:20:00 | === Export Action called ===
2026-07-14 02:20:00 | Input: /path/to/photo.jpg
2026-07-14 02:20:00 | Output: /path/to/photo_processed.jpg
2026-07-14 02:20:00 | JSX script created (action=AutoPortraiture/Portraiture)
2026-07-14 02:20:00 | Launching Photoshop...
2026-07-14 02:20:10 | Photoshop exit code: 0
2026-07-14 02:20:10 | SUCCESS: 15MB: /path/to/photo_processed.jpg
2026-07-14 02:20:10 | Deleted original: /path/to/photo.jpg
2026-07-14 02:20:10 | === Done ===
```

## 常见问题

**导出后没有生成 _processed.jpg**

检查日志文件。确认 PS 中已录制 Action，且 Action 名称和 Set 名称与脚本 CONFIG 中的 `ACTION_NAME` 和 `ACTION_SET` 一致。如果 Action 不存在，JSX 中的 `app.doAction()` 会静默失败（被 try-catch 捕获），照片仍会被保存但未经滤镜处理。

**Portraiture 效果没生效**

确认 Portraiture 插件已正确安装在 Photoshop 中，且录制 Action 时确实执行了 Portraiture 滤镜步骤（不只是打开又关闭了滤镜窗口）。可以在 PS 中手动回放该 Action 验证效果是否生效。

**Photoshop 没有弹到前台**

脚本禁用了 PS 对话框（`app.displayDialogs = DialogModes.NO`），Photoshop 在后台静默处理。处理完成后会收到 macOS 通知。AppleScript 中的 `activate` 行会尝试将 PS 带到前台。

**使用的是其他版本的 Photoshop**

修改脚本中 AppleScript 的 `tell application "Adobe Photoshop 2025"` 为你的实际版本名。

**文件名包含中文**

已验证支持，中文路径可正常处理。

**路径有空格**

LR 传给脚本的路径已正确处理空格，无需额外转义。
