# AutoPortraiture — Lightroom 导出后自动磨皮

> LR 导出 JPEG → Photoshop 回放 Action 调用 Portraiture → 另存为 `<原文件名>_<ACTION_NAME>.jpg` → 清理原文件。  
> 全程自动，通过预录 PS Action 调用滤镜，Action 名称与 PS 版本均可配置。

## 适配环境

| 组件 | 已测试版本 | 未测试版本 |
| --- | --- | --- |
| Adobe Photoshop | 2024、2025、2026 | 其余版本 |
| Lightroom Classic | 14.x | — |
| macOS | 15.x (Apple Silicon) | Intel / 其他 |
| 滤镜插件 | Imagenomic Portraiture 3/4 | — |

> **注意**：`AutoPortraiture.lrplugin/` 目录为已弃用（deprecated）的 Lightroom SDK Lua 插件，不再维护。当前方案使用 `scripts/AutoPortraiture.sh` 导出操作脚本，与该插件无关。

## 工作原理

1. 在 Lightroom 导出对话框的"导出后"下拉菜单中选择 `AutoPortraiture.sh`
2. LR 将导出的 JPEG 路径传给脚本
3. 脚本通过 AppleScript 调起 Photoshop，执行 JSX 脚本
4. JSX 脚本用 `app.doAction(actionName, actionSet)` 回放预录的 Action
5. 另存为 `<原文件名>_<ACTION_NAME>.jpg`，删除原始 JPEG 和临时 PSD
6. macOS 通知提示完成

## 目录结构

```
AutoPortraiture/
├── scripts/
│   └── AutoPortraiture.sh          # 主脚本（Shell → AppleScript → JSX）
├── docs/
│   ├── usage.md                    # 详细使用指南
│   └── troubleshooting.md          # 排错记录（deprecated，历史参考）
├── AutoPortraiture.lrplugin/        # deprecated：LR SDK Lua 插件，不再维护
├── LICENSE
├── README.md
└── .gitignore
```

## 安装

```bash
# 1. 复制脚本到 LR Export Actions 目录
cp scripts/AutoPortraiture.sh ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/
chmod +x ~/Library/Application\ Support/Adobe/Lightroom/Export\ Actions/AutoPortraiture.sh

# 2. 在 PS 中录制 Action（详见 docs/usage.md）
#    Action 名称: Portraiture, Action Set: AutoPortraiture

# 3. 在 LR 导出对话框中，"导出后"选择 AutoPortraiture.sh
```

需要在 Photoshop 中预先录制一个包含 Portraiture 滤镜步骤的 Action。

## 配置

编辑 `scripts/AutoPortraiture.sh` 顶部的 CONFIG 区域：

```bash
# Action 名称和 Action Set 名称（需与 PS 中录制的一致）
ACTION_NAME="Portraiture"
ACTION_SET="AutoPortraiture"

# Photoshop 版本（已测试：2024、2025、2026，其余版本未测试）
PS_VERSION="2025"

# 输出 JPEG 质量 (1-12, 12 = 最高)
JPEG_QUALITY=12
```

输出文件名为 `<原文件名>_<ACTION_NAME>.jpg`，例如 `ACTION_NAME="Portraiture"` 时输出 `photo_Portraiture.jpg`。

修改配置后重新同步到 Export Actions 目录即可生效。

## 技术要点

滤镜调用使用 `app.doAction(actionName, actionSet)` 回放预录的 Photoshop Action。Action 中录制了完整的滤镜操作步骤（包括 Portraiture 的参数设置），回放时自动执行。

| 维度 | 说明 |
| --- | --- |
| 依赖 | 需在 PS 中预录 Action（包含 Portraiture 步骤） |
| 参数 | 录制时锁定（如需调参需重新录制） |
| 切换滤镜 | 需重新录制 Action |
| 对话框 | `app.displayDialogs = DialogModes.NO` 抑制 PS 自身对话框，Action 内的滤镜步骤按录制时的设置执行 |
| PS 版本 | 通过 `PS_VERSION` 配置，已测试 2024/2025/2026 |

详细使用说明见 [docs/usage.md](docs/usage.md)。
