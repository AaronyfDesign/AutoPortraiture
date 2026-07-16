# AutoPortraiture — Lightroom SDK 插件问题排查记录

> **⚠️ DEPRECATED**：本文档记录的是已弃用的 LR SDK Lua 插件方案的排错过程，当前方案（导出操作 Shell 脚本）与这些内容无关，仅供历史参考。

本文档记录了 AutoPortraiture 插件在 Lightroom Classic 14.5.2 (macOS) 上从初始加载到菜单项正常注册过程中遇到的所有问题、排查思路和最终解决方案。

---

## 环境信息

- Lightroom Classic 14.5.2
- macOS (Apple Silicon)
- 插件安装路径：`~/Library/Application Support/Adobe/Lightroom/Modules/AutoPortraiture.lrplugin/`

---

## 问题一：LrToolkitIdentifier was of type nil; string was expected

### 现象

插件加载时弹出错误对话框：

```
In Info.lua file, LrToolkitIdentifier was of type nil; string was expected.
```

### 原因

Lightroom Classic 14.5 要求**所有**插件的 `Info.lua` 中必须包含 `LrToolkitIdentifier` 字段，无论是否设置了 `LrToolkitAccess = true`。这是一个反向域名格式的唯一标识符，用于在 Plugin Manager 中区分不同插件。

### 解决方案

在 `Info.lua` 的 `return` 表中添加：

```lua
LrToolkitIdentifier = "com.autoportraiture.lightroom.plugin",
```

### 经验总结

在 LR 14.x 及以上版本中，`LrToolkitIdentifier` 是事实上的必填字段，即使官方 SDK 文档将其标注为 SDK 1.3 引入的可选字段。缺少此字段会导致插件完全无法加载。

---

## 问题二：No script by the name LrPlugin.PluginInit（7 errors）

### 现象

Plugin Manager 显示 7 条错误，均为：

```
No script by the name LrPlugin.PluginInit
```

### 原因

初始代码将 `PluginInit.lua` 放在 `LrPlugin/` 子目录下，并在 `Info.lua` 中引用为 `LrPlugin.PluginInit`。这里有两个问题：

1. **`Lr` 前缀是 SDK 保留前缀**。以 `Lr` 开头的名称会被 LR 解释为内置 SDK 模块查找（如 `LrApplication`、`LrDialogs`），而不是在插件目录中查找文件。因此 `LrPlugin.PluginInit` 被当作一个不存在的 SDK 模块去加载。

2. **点号路径不会解析为子目录**。与标准 Lua 的 `require` 不同，LR SDK 的脚本引用机制不支持 `A.B` 自动映射为 `A/B.lua`。所有被 `Info.lua` 引用的脚本文件必须直接位于 `.lrplugin` 根目录下。

### 解决方案

将 `PluginInit.lua` 从子目录移出，直接放在 `.lrplugin` 根目录，并在 `Info.lua` 中引用为：

```lua
LrPluginInfoProvider = 'PluginInit',
```

### 经验总结

LR SDK 插件的目录结构是扁平的——所有被 `Info.lua` 直接引用的 Lua 脚本必须位于 `.lrplugin` 根目录。子目录可以用于存放资源文件（如 `Resources/strings_en.lua`），但只能通过 `require` 而非 Info.lua 字段来引用。任何以 `Lr` 开头的名称都会被 SDK 拦截为内置模块查找。

---

## 问题三：Could not find the native function PluginInit（2 errors）

### 现象

修正了目录结构后，仍有 2 条错误：

```
Could not find the native function PluginInit
```

### 原因

这个错误的根因分为两层：

1. **`PluginInit.lua` 在模块加载时崩溃，无法返回有效的表**。具体原因是文件在顶层调用了 `initialize()` 函数，该函数内部调用了 `logger:enable()`。在之前的调试中我们曾错误地认为 `LrLogger` 没有 `enable()` 方法（实际上 SDK 文档确认它是存在的，接受 `'print'` 或 `'logfile'` 参数），但当时的调用方式可能不正确，导致运行时错误。由于错误发生在 `return` 语句之前，LR 无法从该脚本获取到预期的返回表。

2. **`Info.lua` 中的多个 Provider 字段引用了 `PluginInit`，但期望不同的返回类型**。`LrPluginInfoProvider` 期望返回包含 `sectionsForTopOfDialog` 函数的表；而 `LrMetadataProvider`、`LrMetadataTagsetFactory`、`LrExportFilterProvider`、`LrToolbarButtons` 等字段各自期望特定接口类型的返回值。同一个脚本无法同时满足所有这些字段的类型要求。

### 解决方案

1. 移除 `PluginInit.lua` 中顶层的 `initialize()` 调用，确保文件加载时不执行任何可能失败的操作。

2. 从 `Info.lua` 中移除所有引用类型不匹配的字段，只保留 `LrPluginInfoProvider`：

```lua
-- 移除了以下字段：
-- LrMetadataProvider
-- LrMetadataTagsetFactory
-- LrExportFilterProvider
-- LrToolbarButtons
-- LrExternalEditorProvider
```

3. 确保 `PluginInit.lua` 的返回值是一个包含 `sectionsForTopOfDialog` 函数的合法表。

### 经验总结

`Info.lua` 中的每个 Provider/Factory 字段都有严格的返回类型要求。如果引用的脚本返回的表缺少必需的字段或类型不匹配，LR 会报 "Could not find the native function" 错误。调试时应逐个添加字段，而不是一次性注册所有 Provider。

另外需要特别注意：被 `Info.lua` 引用的脚本在**加载时**（`require` 阶段）不应执行任何可能失败的副作用代码，所有初始化逻辑应放在返回表的回调函数内部。

---

## 问题四：import 'LrCatalog' 不存在

### 现象

`PostProcess.lua` 中的 `import 'LrCatalog'` 导致加载失败。

### 原因

`LrCatalog` 不是一个有效的 SDK 可导入模块。LR SDK 中目录（Catalog）对象是通过 `LrApplication.activeCatalog()` 方法获取的实例，而不是一个可以 `import` 的独立模块。

### 解决方案

删除 `import 'LrCatalog'` 这一行。在需要使用 catalog 的地方通过 `LrApplication.activeCatalog()` 获取：

```lua
local catalog = LrApplication.activeCatalog()
```

### 经验总结

并非所有 LR 对象都有对应的可导入模块。SDK 中可以 `import` 的模块列表是固定的（如 `LrApplication`、`LrDialogs`、`LrTasks` 等）。当不确定某个模块是否存在时，应查阅 SDK 文档中的模块列表。

---

## 问题五：非 ASCII 字符导致潜在解析问题

### 现象

虽然没有直接报错，但 LR 的 Lua 解释器对非 ASCII 字符的处理存在不确定性，可能导致某些环境下的静默失败。

### 原因

源代码中包含以下 Unicode 字符：

- `…`（U+2026，水平省略号）
- `—`（U+2014，破折号）
- `→`（U+2192，右箭头）
- `©`（U+00A9，版权符号）

这些字符在字符串字面量中使用时，可能在某些 LR 版本的 Lua 5.1 解释器中引发解析错误。

### 解决方案

将所有 `.lua` 文件中的非 ASCII 字符替换为 ASCII 等价物：

| 原字符 | 替换为 |
|--------|--------|
| `…`    | `...`  |
| `—`    | `-`    |
| `→`    | `->`   |
| `©`    | `(c)`  |

### 经验总结

LR SDK 插件的 Lua 文件应保持纯 ASCII 编码。非 ASCII 内容（如国际化字符串）应通过 LR 的本地化机制（`LOC` 函数 + TranslatedStrings 文件）来处理，而不是直接嵌入源代码。

---

## 问题六：菜单项不出现在「增效工具额外信息」子菜单中

### 现象

Plugin Manager 显示插件状态为「已启用」，无任何错误，控制台日志也没有插件相关的报错。但用户在「文件 > 增效工具额外信息」和「图库 > 增效工具额外信息」中均看不到 AutoPortraiture 的菜单项。同样，一个只有 Info.lua 和 main.lua 的最小测试插件（TestPlugin）的菜单项也不出现。

### 排查过程

1. **确认插件已加载**：Plugin Manager 显示插件已启用，版本号正确，无诊断信息。排除了插件未加载的可能。

2. **检查日志**：`lrc_console.log` 中没有任何插件相关的错误。排除了加载时静默失败的可能。

3. **检查文件权限和属性**：文件权限正确（644），无 macOS Gatekeeper 隔离标记（quarantine attribute），文件内容纯 ASCII。排除了系统层面的阻止。

4. **检查 SDK 版本号**：通过解析内置 Aperture 插件的编译字节码，确认内置插件使用 `LrSdkVersion = 5.0`。但 SDK 文档的版本历史表明 LR 14.5 支持到 SDK 14.5，所以 `LrSdkVersion = 14.0` 是合法的。排除了 SDK 版本不兼容的可能。

5. **对比内置插件的字段名**：关键发现——内置 Aperture 插件使用的字段名是 `LrExportMenuItems`（对应 File > Plug-in Extras），而不是 `LrFileMenuItems`。查阅 SDK 文档确认了 LR 中菜单注册的三个合法字段名。

### 原因

`Info.lua` 中使用了 **`LrFileMenuItems`** 作为菜单注册字段名。**这个字段名在 LR SDK 中不存在**。LR 对 `Info.lua` 中的未知字段采取静默忽略策略——不报错，但也不会注册任何菜单项。

SDK 中合法的菜单注册字段为：

| Info.lua 字段名 | 对应菜单位置 | SDK 版本 |
|-----------------|-------------|---------|
| `LrExportMenuItems` | 文件 (File) > 增效工具额外信息 (Plug-in Extras) | 1.3 |
| `LrLibraryMenuItems` | 图库 (Library) > 增效工具额外信息 (Plug-in Extras) | 1.3 |
| `LrHelpMenuItems` | 帮助 (Help) > 增效工具额外信息 (Plug-in Extras) | 3.0 |

注意 `LrLibraryMenuItems` 对应的菜单只在**图库模块**下可见。如果用户当前在「修改照片」等其他模块中，是看不到这些菜单项的。

### 解决方案

将 `LrFileMenuItems` 修改为 `LrExportMenuItems`：

```lua
-- 错误写法（LR 会静默忽略）
LrFileMenuItems = { ... }

-- 正确写法
LrExportMenuItems = { ... }
```

最终 `Info.lua` 同时注册了两个菜单位置，确保用户在不同模块下都能访问：

```lua
LrExportMenuItems = {
    { title = "AutoPortraiture - Retouch in Photoshop", file = "main.lua" },
    { title = "AutoPortraiture - Batch Retouch",        file = "main.lua" },
},
LrLibraryMenuItems = {
    { title = "AutoPortraiture - Retouch in Photoshop", file = "main.lua" },
    { title = "AutoPortraiture - Batch Retouch",        file = "main.lua" },
},
```

### 经验总结

LR SDK 对 `Info.lua` 中的未知字段采取**静默忽略**策略，不会产生任何错误日志。这使得字段名拼写错误非常难以排查。调试时应严格对照 SDK 文档中的字段名列表，必要时可以对比 LR 内置插件（位于 `/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app/Contents/PlugIns/`）的 `Info.lua` 来确认正确的字段名。

另外要注意「File > Plug-in Extras」对应的字段名是 `LrExportMenuItems`（而非直觉上的 `LrFileMenuItems`）。这个命名源于 SDK 1.3 时代，当时该菜单项主要用于导出相关的操作。

---

## 附录：LR SDK 开发备忘

### Info.lua 运行环境限制

`Info.lua` 运行在一个受限环境中，只有以下内容可用：`string` 命名空间、`LOC()` 函数、`WIN_ENV` / `MAC_ENV` 全局变量、`_VERSION`。不可使用 `import` 或 `require`。

### 插件安装路径

| 平台 | 路径 |
|------|------|
| macOS（当前用户） | `~/Library/Application Support/Adobe/Lightroom/Modules/` |
| macOS（所有用户） | `/Library/Application Support/Adobe/Lightroom/Modules/` |
| Windows（当前用户） | `%APPDATA%\Adobe\Lightroom\Modules\` |

放在 Modules 文件夹中的插件会自动加载，无法通过 Plugin Manager 移除（只能禁用）。

### SDK 版本与 LR 版本对应关系

SDK 版本号与 LR 应用版本号**不是同一个数字**，但从 SDK 10.0 开始两者开始趋于接近。LR 14.5 支持 SDK 版本最高到 14.5。建议 `LrSdkVersion` 设置为当前目标 LR 版本支持的最高值，`LrSdkMinimumVersion` 设置为插件实际依赖的最低 API 版本。

### LrLogger 使用

```lua
local logger = import 'LrLogger'('MyPlugin')
logger:enable('print')    -- 输出到控制台（开发时使用）
logger:enable('logfile')  -- 输出到日志文件

logger:info("message")
logger:warn("message")
logger:error("message")
```

日志文件位置：`~/Library/Logs/Adobe/Lightroom/LrClassicLogs/`（macOS）。

### 调试建议

1. 修改插件文件后必须**重启 Lightroom**，LR 不支持热重载插件。
2. 使用 `lrc_console.log`（位于 `~/Library/Application Support/Adobe/Lightroom/`）查看启动时的错误信息。
3. `Info.lua` 中的未知字段会被静默忽略，字段名拼写错误不会产生任何提示。
4. 可以查看 LR 内置插件的结构作为参考，路径为 LR 应用程序包内的 `Contents/PlugIns/` 目录。
5. 创建最小化测试插件（只有 Info.lua + main.lua）是隔离问题的有效方法。
