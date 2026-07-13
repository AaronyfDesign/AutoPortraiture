# AutoPortraiture 本地脚本方案 — 设计文档

## 背景

原方案基于 Lightroom SDK 插件实现全流程：LR 导出 → Photoshop + Portraiture → 回传 LR。实际开发中发现 LR SDK 的限制较多（模块加载机制严格、调试周期长、跨版本兼容性脆弱），而磨皮/降噪这类工作流末端的操作步骤本质上不依赖 Lightroom，完全可以脱离 LR 框架，用本地脚本直接实现。

## 方案概述

将工作流拆分为两段：

1. **LR 侧**：用户在 Lightroom 中用原生导出功能（或导出预设）将选中照片导出为 16-bit TIFF 到约定的输入文件夹。
2. **本地脚本侧**：脚本扫描输入文件夹，调用 Photoshop + Portraiture 批量执行磨皮，输出 PSD 到约定的输出文件夹。

用户可手动将输出文件夹中的 PSD 导入回 Lightroom，或将输出文件夹配置为 LR 的「自动导入」监视目录实现半自动回传。

## 目录结构

```
AutoPortraiture/
├── scripts/
│   ├── run.sh                     # 主入口：扫描输入文件夹 → 调用 Photoshop
│   ├── PortraitureAction.jsx      # Photoshop ExtendScript：Portraiture 调用 + 保存
│   └── watch.sh                   # 可选：文件夹监视，自动触发 run.sh
├── config/
│   └── presets.json               # 预设参数定义（可选，默认硬编码 Subtle）
├── input/                         # 约定的输入文件夹（放置待处理 TIFF）
├── output/                        # 约定的输出文件夹（PSD 产出）
├── docs/
│   └── design.md                  # 本文档
└── README.md
```

## 工作流程

```
Lightroom 导出 TIFF          本地脚本                    Lightroom 导入
┌─────────────┐     ┌──────────────────────────┐     ┌─────────────┐
│  选中照片    │     │  run.sh                  │     │  手动导入    │
│  导出为      │────▶│  扫描 input/ 下所有 TIFF  │────▶│  或自动导入  │
│  16-bit TIFF│     │  调用 Photoshop + JSX    │     │  (监视 output/)│
│  到 input/  │     │  Portraiture 磨皮        │     │             │
└─────────────┘     │  保存 PSD 到 output/    │     └─────────────┘
                    └──────────────────────────┘
```

## 核心组件

### run.sh — 主入口脚本

职责：扫描 `input/` 目录下的 TIFF 文件，逐个调用 Photoshop 执行 JSX 脚本。

调用 Photoshop 的方式（macOS，通过 AppleScript 桥接）：

```bash
osascript -e 'tell application "Adobe Photoshop 2024"
  do javascript of (read POSIX file "/path/to/PortraitureAction.jsx") \
    with arguments {"--file", "/path/to/image.tiff", "--output", "/path/to/output.psd"}
end tell'
```

脚本流程：

1. 检测 Photoshop 是否已安装、路径是否有效
2. 扫描 `input/` 目录下的 `.tif` / `.tiff` 文件
3. 对每个文件调用 Photoshop 执行 PortraitureAction.jsx
4. 等待执行完成，检查输出文件是否生成
5. 处理完成后输出汇总（成功数 / 失败数 / 失败文件列表）
6. 可选：将已处理的输入文件移动到 `input/processed/` 子目录

关键设计点：

- **默认预设**：硬编码 Subtle（smoothing=25, texture=15, pores=90, sharpening=25），满足最低程度磨皮的常规需求
- **超时检测**：每个文件设定超时时间（默认 120 秒），超时后跳过并记录
- **错误容错**：单张失败不中断整个批次
- **日志**：输出到终端 + 写入 `logs/autoportraiture.log`

### PortraitureAction.jsx — Photoshop 脚本

从原方案继承，做以下调整：

- 去掉命令行参数解析逻辑（改由 run.sh 通过 AppleScript `with arguments` 传入）
- 改为接收文件路径数组，内部循环处理
- 默认使用 Subtle 预设参数，脚本顶部留出可配置常量
- 保存为 PSD 后关闭文档

核心参数（Subtle 预设）：

| 参数 | 值 | 说明 |
| --- | --- | --- |
| smoothing | 25 | 皮肤平滑 |
| texture | 15 | 纹理平滑 |
| pores | 90 | 毛孔保留 |
| sharpening | 25 | 锐化 |

### watch.sh — 文件夹监视（可选）

使用 `fswatch` 监视 `input/` 目录，有新文件写入且稳定后自动触发 `run.sh`：

```bash
fswatch -0 --event Created --event Updated ~/AutoPortraiture/input/ | while read -d "" event; do
  # 等待文件写入稳定
  sleep 3
  ~/AutoPortraiture/scripts/run.sh
done
```

依赖：`fswatch`（macOS 可通过 `brew install fswatch` 安装）。

### LR 自动导入配置（可选）

在 Lightroom 中配置「自动导入」：

1. File → Auto Import → Auto Import Settings
2. 勾选「Enable Auto Import」
3. Watched Folder 设为 `~/AutoPortraiture/output/`
4. Destination 设为实际照片库目录

这样脚本处理完的 PSD 会自动导入到 Lightroom 目录中。

## 与原 LR 插件方案的对比

| 维度 | LR 插件方案 | 本地脚本方案 |
| --- | --- | --- |
| 依赖 | 需要开发 Lua 插件，受 SDK 限制 | 仅需 shell + Photoshop |
| 安装 | 复制 .lrplugin 到 Modules 目录 | 直接运行脚本 |
| 调试 | 需在 Plugin Manager 中 Reload，日志通过 LrLogger | 终端直接运行，标准输出 |
| 自动回传 LR | 支持（SDK API 自动导入 + 堆叠） | 半自动（依赖 LR 自动导入或手动导入） |
| 堆叠原图 | 支持 | 不支持（需手动堆叠） |
| 跨平台 | 需分别处理 macOS / Windows 路径 | 当前面向 macOS（Windows 可用 PowerShell 替代） |
| 维护成本 | 高（SDK 版本兼容、模块加载陷阱） | 低（标准 shell + JSX） |
| 灵活性 | 受限于 LR SDK 能力 | 可自由扩展（结合其他 CLI 工具） |

## 风险与缓解

**Portraiture 弹窗**：Portraiture 的 `dontDisplay` 模式是否能完全抑制 UI 需要实际测试。如果每张照片都弹窗，批处理体验会很差。缓解方案是先用单张文件测试确认，若不支持无头模式则考虑用 Photoshop 的 Action（动作）录制 Portraiture 操作后通过批处理执行。

**Photoshop 稳定性**：长时间批量处理时 Photoshop 可能卡死。脚本需实现超时检测（`timeout` 命令或轮询输出文件），超时后强制终止并重试。

**文件写入完整性**：需等待 PSD 文件大小稳定后再判定为处理完成，防止读取未写完的文件。复用原方案中的稳定性检测逻辑（两次读取文件大小一致）。

**Photoshop 版本路径**：macOS 上不同版本的 Photoshop 安装路径不同（`Adobe Photoshop 2024.app` vs `2023.app` 等）。脚本中按版本号从新到旧依次检测，取第一个有效路径。

## 实施计划

1. 重构 `PortraitureAction.jsx`：简化为接收文件路径数组、默认 Subtle 预设、内部循环处理
2. 编写 `run.sh`：Photoshop 路径检测、文件扫描、AppleScript 调用、超时与错误处理
3. 编写 `watch.sh`（可选）：fswatch 监视 + 自动触发
4. 编写 README：使用说明、配置方法、常见问题
5. 测试：单文件 → 批量 → 文件夹监视

## 默认配置

```bash
# run.sh 顶部可配置项
INPUT_DIR="$HOME/AutoPortraiture/input"
OUTPUT_DIR="$HOME/AutoPortraiture/output"
PROCESSED_DIR="$HOME/AutoPortraiture/input/processed"
LOG_FILE="$HOME/AutoPortraiture/logs/autoportraiture.log"
TIMEOUT=120                    # 单文件超时（秒）
PRESET="Subtle"                # 默认预设
# Subtle 预设参数
SMOOTHING=25
TEXTURE=15
PORES=90
SHARPENING=25
```
