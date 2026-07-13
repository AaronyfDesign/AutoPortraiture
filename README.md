# AutoPortraiture — Lightroom SDK 插件框架

> **一键磨皮工作流插件**：Lightroom → Photoshop → Portraiture → 回传 Lightroom。  
> 消除手动导出 TIFF 来回搬运的痛点。

## 项目概述

AutoPortraiture 是一个基于 Adobe Lightroom SDK 的自动化插件，将 Lightroom 选中的照片自动发送到 Photoshop，通过 Portraiture 插件执行专业磨皮处理，然后将处理结果以 PSD 格式自动回传到 Lightroom 目录中，并可选与原图堆叠。

整个流程无需手动导出/导入文件，大幅提升人像修图效率。

## 仓库结构

本项目遵循 Lightroom 插件标准规范，插件以 `.lrplugin` 目录（bundle）形式组织。仓库根目录包含插件 bundle 和项目级文档：

```
AutoPortraiture/                         # 仓库根目录
├── AutoPortraiture.lrplugin/            # Lightroom 插件 bundle（安装时复制此目录）
│   ├── Info.lua                         # 插件清单（manifest）：元信息、菜单注册、外部编辑器集成
│   ├── main.lua                         # 核心工作流：异步任务编排、导出、Photoshop 启动、进度反馈
│   ├── PortraitureAction.jsx            # Photoshop 脚本：调用 Portraiture 插件、5 个预设、自动保存
│   ├── PostProcess.lua                  # 后处理：文件监控、回传 Lightroom、堆叠原始照片
│   ├── PluginInit.lua                  # 插件生命周期、偏好设置、快捷键注册
│   └── Resources/
│       └── strings_en.lua               # 英文本地化（30+ 字符串）
├── README.md                            # 完整使用指南（本文件）
├── LICENSE                              # MIT 许可证
└── .gitignore                           # Git 忽略规则
```

### 关于 .lrplugin 格式

Lightroom 插件必须以 `.lrplugin` 为扩展名的目录形式存在。该目录在 macOS 上会被 Finder 当作包（package）处理，右键可选择「显示包内容」查看内部文件；在 Windows 上则作为普通文件夹显示。`Info.lua` 是 Lightroom SDK 识别的清单文件，必须位于 `.lrplugin` 目录的根级。

开发时可使用 `.lrdevplugin` 扩展名，这样 macOS Finder 会将其作为普通文件夹显示，方便编辑：

```bash
# 开发模式：创建 .lrdevplugin 符号链接
ln -s AutoPortraiture.lrplugin AutoPortraiture.lrdevplugin
```

### 文件说明

| 文件 | 说明 |
| --- | --- |
| `Info.lua` | 插件清单：SDK 版本、菜单注册、导出过滤器、外部编辑器、工具栏按钮、默认偏好 |
| `main.lua` | 核心工作流：异步任务编排、TIFF 导出、Photoshop 启动、JSX 脚本调用、进度反馈 |
| `PortraitureAction.jsx` | Photoshop ExtendScript：Portraiture 插件调用、5 个预设、锐化、PSD 保存 |
| `PostProcess.lua` | 后处理：PSD 文件监控、文件大小稳定性检测、回传 Lightroom、堆叠原图 |
| `PluginInit.lua` | 插件生命周期：初始化、偏好迁移、设置对话框、快捷键注册、关闭清理 |
| `Resources/strings_en.lua` | 英文本地化字符串（30+ 条），包含菜单、进度、错误、设置等全部用户可见文本 |

## 核心设计

- **异步架构**：使用 `LrTasks.startAsyncTask` + `LrFunctionContext`，Lightroom UI 在处理过程中不冻结。
- **跨平台**：自动检测 macOS / Windows 系统下的 Photoshop 安装路径，支持 PS 2020–2024。
- **5 个内置预设**：Subtle / Light Smoothing / Medium Smoothing / Strong Smoothing / Portrait，覆盖从轻度到重度磨皮需求。
- **文件稳定性检测**：在回传前等待文件大小稳定，防止读取 Photoshop 尚未写完的文件。
- **错误容错**：单张照片处理失败不影响整个批次，错误信息写入日志。
- **调试日志**：集成 `LrLogger`，独立日志通道 `AutoPortraiture`，支持 info/warn 级别切换。

## 安装步骤

### 1. 安装插件

将 `AutoPortraiture.lrplugin` 目录复制到 Lightroom 模块目录：

- **macOS**：`~/Library/Application Support/Adobe/Lightroom/Modules/`
- **Windows**：`C:\Users\<username>\AppData\Roaming\Adobe\Lightroom\Modules\`

> 注意：必须复制整个 `.lrplugin` 目录，不要只复制目录内的单个文件。不要重命名目录，`.lrplugin` 扩展名是 Lightroom 识别插件的依据。

### 2. 重启 Lightroom

打开 Lightroom，进入 **File → Plugin Manager**，点击 **Add** 按钮，选择 `AutoPortraiture.lrplugin` 目录并启用。

### 3. 配置偏好

在 Plugin Manager 中选择 AutoPortraiture → **Settings**，配置以下选项：

- 磨皮预设（Subtle / Light / Medium / Strong / Portrait）
- 输出格式（PSD 推荐 / TIFF / JPEG）
- Photoshop 超时时间（默认 120 秒）
- 是否与原图堆叠
- 是否等待文件大小稳定
- 是否抑制 Portraiture 对话框
- 是否启用调试日志

## 使用方法

| 方式 | 操作 |
| --- | --- |
| 菜单 | Library → AutoPortraiture - Retouch in Photoshop |
| 快捷键 | macOS: `Cmd + Option + P` / Windows: `Ctrl + Alt + P` |
| 右键 | 右键照片 → Edit In → AutoPortraiture |
| 工具栏 | 点击工具栏上的 Retouch 按钮 |

选中一张或多张照片后，通过上述任一方式启动工作流即可。

## 工作流程

1. 照片从 Lightroom 导出为 16-bit TIFF（临时目录）
2. Photoshop 自动打开图片
3. `PortraitureAction.jsx` 脚本执行 Portraiture 磨皮（使用选定的预设参数）
4. 应用锐化并保存为 PSD（保留图层）
5. Lightroom 自动重新导入处理后的 PSD 文件
6. 与原图堆叠（可选，默认开启）
7. 清理临时 TIFF 文件

## 预设参数

| 预设 | 皮肤平滑 | 纹理平滑 | 毛孔保留 | 锐化 |
| --- | --- | --- | --- | --- |
| Subtle | 25 | 15 | 90 | +25 |
| Light Smoothing | 40 | 25 | 80 | +20 |
| Medium Smoothing | 65 | 40 | 65 | +15 |
| Strong Smoothing | 80 | 55 | 50 | +10 |
| Portrait | 70 | 35 | 70 | +18 |

## 注意事项

- 需要 **Photoshop 2020 或更高版本**，且 Portraiture 插件已安装。
- Portraiture 的 **"dontDisplay" 模式**可避免弹窗阻塞自动化流程（默认开启）。
- 大文件（如高像素 RAW）处理时间较长，可在设置中增大 `psTimeout` 偏好值。
- 调试日志位置：macOS `~/Library/Logs/Adobe/Lightroom/`，Windows 事件查看器。
- 建议在 Lightroom → Edit → Keyboard Shortcuts 中为菜单项分配快捷键。

## 技术细节

### .lrplugin bundle 内部路径解析

Lightroom SDK 中 `_PLUGIN.path` 自动指向 `.lrplugin` 目录的绝对路径。插件内所有文件通过 `LrPathUtils.child(_PLUGIN.path, filename)` 解析相对路径，`require()` 则以 `.lrplugin` 目录为根进行模块加载。因此 `require("PostProcess")` 会加载同级的 `PostProcess.lua`，`require("PluginInit")` 会加载同级的 `PluginInit.lua`。

### 异步任务架构

`main.lua` 使用 `LrTasks.startAsyncTask` 在后台线程中执行整个工作流，通过 `LrFunctionContext` 管理任务生命周期，`LrProgressScope` 提供进度反馈。Lightroom 主界面在处理期间保持响应。

### 跨平台 Photoshop 路径检测

`main.lua` 中的 `getPhotoshopPath()` 函数按版本号从新到旧依次检查 macOS 和 Windows 上的 Photoshop 安装路径，返回第一个找到的有效路径。

### 文件稳定性检测

`PostProcess.lua` 中的 `isFileStable()` 函数在固定间隔内连续读取文件大小，当两次读取的大小一致时认为文件写入完成。这防止了 Photoshop 仍在保存时读取不完整文件的问题。

### 错误容错机制

每个照片的处理都包裹在 `pcall`（Lua）和 `try/catch`（JSX）中，单张照片失败不会中断整个批次。失败信息记录到日志通道，用户可在处理完成后查看汇总。

## 开发与调试

### 开发模式

开发时建议使用 `.lrdevplugin` 扩展名，macOS Finder 会将其作为普通文件夹显示，方便直接编辑内部文件：

```bash
cd ~/Library/Application\ Support/Adobe/Lightroom/Modules/
ln -s /path/to/repo/AutoPortraiture.lrplugin AutoPortraiture.lrdevplugin
```

修改代码后在 Plugin Manager 中点击 **Reload** 即可重新加载插件，无需重启 Lightroom。

### 启用调试日志

在 Plugin Manager → AutoPortraiture → Settings 中勾选 "Enable debug logging"，日志将输出到 `AutoPortraiture` 通道。

macOS 查看日志：
```bash
log stream --predicate 'subsystem == "com.adobe.lightroom"' --info
```

### 修改预设

在 `main.lua` 的 `PRESETS` 表和 `PortraitureAction.jsx` 的 `PRESETS` 对象中同步修改预设参数。两处定义必须保持一致。

### 添加新的本地化

1. 在 `.lrplugin/Resources/` 目录下创建新的字符串文件，如 `strings_zh.lua`
2. 参照 `strings_en.lua` 的结构定义所有字符串键值
3. 在 `Info.lua` 中注册本地化资源

## 版本历史

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| 1.2.0 | 2024-06-15 | 新增 Portrait 预设；文件稳定性检测优化；`LrToolkitAccess` 启用 |
| 1.1.0 | 2024-03-20 | 新增跨平台 PS 路径检测；偏好设置迁移机制 |
| 1.0.0 | 2024-01-15 | 初始版本：完整 LR→PS→Portraiture→LR 工作流 |

## 许可证

MIT License — 详见 [LICENSE](LICENSE)

## 相关链接

- [学城文档](https://km.sankuai.com/collabpage/2773930029)
- [Adobe Lightroom SDK 文档](https://developer.adobe.com/lightroom-classic/)
- [Lightroom 插件安装指南](https://presets.io/a/blog/lightroom-how-to-install-and-manage-plugins)
- [Portraiture 插件官网](https://www.imagenomic.com/Products/Portraiture)
