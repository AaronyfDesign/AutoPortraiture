return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrPluginName = "AutoPortraiture",
    LrToolkitIdentifier = "com.autoportraiture.lightroom.plugin",
    LrPluginInfoProvider = 'PluginInit',
    LrExportMenuItems = {
        {
            title = "AutoPortraiture - Retouch in Photoshop",
            file = "main.lua",
        },
        {
            title = "AutoPortraiture - Batch Retouch",
            file = "main.lua",
        },
    },
    LrLibraryMenuItems = {
        {
            title = "AutoPortraiture - Retouch in Photoshop",
            file = "main.lua",
        },
        {
            title = "AutoPortraiture - Batch Retouch",
            file = "main.lua",
        },
    },
    VERSION = {
        major = 1,
        minor = 2,
        revision = 0,
        build = 20240615,
    },
    LrPluginCopyright = "(c) 2024 AutoPortraiture Project",
    LrPluginDescription = "One-click skin retouching workflow: Lightroom -> Photoshop -> Portraiture -> Lightroom.",

    LrPluginDefaultPreferences = {
        preset = "Medium Smoothing",
        outputFormat = "PSD",
        outputBitDepth = 16,
        psTimeout = 120,
        waitForFileStability = true,
        fileStabilityInterval = 2,
        stackWithOriginal = true,
        debugLogging = false,
        dontDisplayPortraiture = true,
    },
}
