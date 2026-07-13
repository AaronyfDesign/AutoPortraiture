# AutoPortraiture 使用指南

## 环境要求

- macOS
- Lightroom Classic（已测试 14.5.2）
- Adobe Photoshop（已测试 2025）
- 滤镜插件（可选）：如 Imagenomic Portraiture、Camera Raw 等，需安装在 Photoshop 中

## 安装

### 1. 安装脚本

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
chmod +x ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/AutoPortraiture.sh
```

### 2. 配置滤镜标识符

脚本通过 `executeAction(stringIDToTypeID(FILTER_ID), ...)` 直接调用滤镜，不需要预录 Photoshop Action。只需在 CONFIG 区配置滤镜的标识符即可。JSX 内部会先尝试 stringID 调用，失败后自动回退到 charID（4 字符代码）调用，兼容只注册了 charID 的老滤镜。

已知的常用滤镜标识符：

| 滤镜 | FILTER_ID | 说明 |
| --- | --- | --- |
| Camera Raw Filter | `AdobeCameraRawFilter` | PS 内置 ✓ 已测试 |
| Twirl (旋转扭曲) | `twirl` | PS 内置 ✓ 已测试 |
| Gaussian Blur | `GaussianBlur` | PS 内置高斯模糊 |
| Surface Blur | `surfaceBlur` | PS 内置表面模糊 |
| Portraiture 3/4 | 需查询 | 安装后用 ScriptingListener 插件查询 |

如果使用 Portraiture 或其他第三方滤镜，需要查询其 string ID：

1. 安装 Adobe ScriptingListener 插件（PS 附带，位于 `Adobe Photoshop 2025/Plug-ins/Automate/` 目录下）
2. 在 PS 中手动运行一次该滤镜
3. 打开 `~/Desktop/ScriptingListenerJS.log`，找到对应的 `executeAction` 调用
4. 复制其中的 `stringIDToTypeID("xxx")` 里的字符串
5. 填入脚本的 `FILTER_ID` 配置项

### 3. 在 Lightroom 中配置导出

在 Lightroom 中选中照片，按 `Cmd + Shift + E` 打开导出对话框：

1. 图像格式：JPEG
2. 质量：100%
3. 向下滚动到"导出后"（Post-Processing）下拉菜单
4. 选择 `AutoPortraiture.sh`
5. 点击导出

导出完成后，脚本自动运行：Photoshop 打开 JPEG → 调用滤镜 → 另存为 `<原文件名>_processed.jpg` → 删除原始 JPEG → 清理临时文件 → 弹出 macOS 通知。

## 配置参数

编辑 `scripts/AutoPortraiture.sh` 顶部 CONFIG 区域：

```bash
# 滤镜标识符（Photoshop 内部 string ID）
FILTER_ID="AdobeCameraRawFilter"

# 滤镜调用时是否显示对话框
# ALL = 显示滤镜界面（可手动调参）
# NO  = 静默执行（用默认参数，不弹窗）
FILTER_DIALOG_MODE="ALL"

# 滤镜对话框弹出后自动点击 OK
# yes = 自动点击（Twirl、Portraiture 等需确认的滤镜推荐开启）
# no  = 等待手动点击
AUTO_CLICK_OK="yes"

# 输出 JPEG 质量 (1-12, 12 = 最高)
JPEG_QUALITY=12
```

修改后同步到 Export Actions 目录：

```bash
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
```

切换滤镜只需修改 `FILTER_ID` 一行。例如从 Camera Raw 切换到高斯模糊：

```bash
FILTER_ID="GaussianBlur"
FILTER_DIALOG_MODE="NO"   # 高斯模糊不需要交互界面，设为 NO 静默执行
```

## 批量处理

在 Lightroom 中选中多张照片后导出，LR 会逐张导出 JPEG 并为每张调用一次脚本。Photoshop 依次处理每张照片，全程无需手动干预（当 `FILTER_DIALOG_MODE="NO"` 时）。处理完成后每张照片都会收到 macOS 通知。

如果 `FILTER_DIALOG_MODE="ALL"` 且 `AUTO_CLICK_OK="yes"`，每张照片处理时弹出滤镜界面后会自动点击 OK，全程无需手动干预。适合 Twirl、Portraiture 等需要点击确认才能载入效果的滤镜。

如果 `AUTO_CLICK_OK="no"`，则滤镜界面弹出后等待手动点击确定，适合需要逐张调参的场景。

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
2026-07-14 02:12:25 | === Export Action called ===
2026-07-14 02:12:25 | Input: /tmp/ap_autoclick_test.jpg
2026-07-14 02:12:25 | Output: /tmp/ap_autoclick_test_processed.jpg
2026-07-14 02:12:25 | JSX script created (filter=twirl)
2026-07-14 02:12:25 | Auto-clicker started (PID=60751)
2026-07-14 02:12:25 | Launching Photoshop...
2026-07-14 02:12:30 | Photoshop exit code: 0
2026-07-14 02:12:30 | Auto-clicker stopped
2026-07-14 02:12:30 | SUCCESS: 15MB: /tmp/ap_autoclick_test_processed.jpg
2026-07-14 02:12:30 | Deleted original: /tmp/ap_autoclick_test.jpg
2026-07-14 02:12:30 | === Done ===
```

## 常见问题

**导出后没有生成 _processed.jpg**

检查日志文件。确认 `FILTER_ID` 配置的滤镜标识符正确。如果标识符错误，JSX 中的 `executeAction` 会静默失败（被 try-catch 捕获），照片仍会被保存但未经滤镜处理。

**滤镜标识符怎么查**

安装 ScriptingListener 插件后，在 PS 中手动运行一次目标滤镜，然后查看 `~/Desktop/ScriptingListenerJS.log` 文件，其中会记录对应的 `executeAction` 调用及 `stringIDToTypeID` 参数。

**Photoshop 没有弹到前台**

脚本禁用了 PS 对话框，Photoshop 在后台静默处理（当 `FILTER_DIALOG_MODE="NO"` 时）。处理完成后会收到 macOS 通知。如果需要 PS 可见，AppleScript 中的 `activate` 行会尝试将 PS 带到前台。

**自动点击 OK 不生效**

自动点击功能依赖 macOS 的辅助功能（Accessibility）权限。首次运行时系统可能弹出授权提示，需要在「系统设置 → 隐私与安全 → 辅助功能」中为运行脚本的终端应用（如 Terminal、iTerm 或 Lightroom）授权。授权后重新运行即可。

**使用的是其他版本的 Photoshop**

修改脚本中 AppleScript 的 `tell application "Adobe Photoshop 2025"` 为你的实际版本名。

**文件名包含中文**

已验证支持，中文路径可正常处理。

**路径有空格**

LR 传给脚本的路径已正确处理空格，无需额外转义。
