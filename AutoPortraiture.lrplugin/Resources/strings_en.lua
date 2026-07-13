--[[
    AutoPortraiture - Lightroom SDK Plugin
    Resources/strings_en.lua - English localization (30+ strings)

    All user-facing strings are centralized here for easy translation.
    Access via: local s = require("Resources.strings_en").strings
]]

local strings = {
    -- Plugin identity
    pluginName           = "AutoPortraiture",
    pluginDescription    = "One-click skin retouching workflow: Lightroom -> Photoshop -> Portraiture -> Lightroom",

    -- Menu items
    menuRetouch          = "AutoPortraiture - Retouch in Photoshop",
    menuBatchRetouch     = "AutoPortraiture - Batch Retouch",
    menuSettings         = "AutoPortraiture - Settings",

    -- Toolbar
    toolbarRetouchTitle  = "Retouch",
    toolbarRetouchTooltip = "Send selected photos to Photoshop with Portraiture",

    -- Progress messages
    progressExporting    = "Exporting photos as TIFF...",
    progressProcessing   = "Processing in Photoshop...",
    progressReimporting  = "Re-importing retouched photos...",
    progressExportingItem = "Exporting %s (%d/%d)",
    progressImportingItem = "Importing %s (%d/%d)",

    -- Completion messages
    completeMessage      = "AutoPortraiture complete: %d photo(s) retouched and imported.",
    completeBezel        = "AutoPortraiture workflow started",
    settingsSaved        = "AutoPortraiture settings saved",

    -- Error messages
    errorNoPhotos        = "No photos selected. Please select at least one photo.",
    errorNoExport        = "No photos were exported. Aborting.",
    errorNoPhotoshop     = "Photoshop not found. Please install Photoshop 2020 or later.",
    errorNoJSX           = "PortraitureAction.jsx not found at: %s",
    errorTimeout         = "Photoshop processing timed out. Try increasing the timeout in plugin settings.",
    errorNoPSD           = "No PSD files were produced by Photoshop. Check that Portraiture is installed and functioning.",
    errorPortraitureFail = "Portraiture processing failed for one or more photos.",
    errorImport          = "Failed to import %s: %s",

    -- Settings dialog labels
    settingsTitle        = "AutoPortraiture Settings",
    settingsPresetLabel  = "Retouching Preset",
    settingsFormatLabel  = "Output Format",
    settingsTimeoutLabel = "Photoshop Timeout (sec)",
    settingsStabilityLabel = "File Stability Check (sec)",
    settingsStackLabel   = "Stack retouched photos with originals",
    settingsWaitLabel    = "Wait for file size stability before re-import",
    settingsDontDisplayLabel = "Suppress Portraiture dialog (dontDisplay mode)",
    settingsDebugLabel   = "Enable debug logging (LrLogger: AutoPortraiture)",
    settingsSaveButton   = "Save",
    settingsCancelButton = "Cancel",

    -- Preset names
    presetSubtle         = "Subtle",
    presetLight          = "Light Smoothing",
    presetMedium         = "Medium Smoothing",
    presetStrong         = "Strong Smoothing",
    presetPortrait       = "Portrait",

    -- Output format options
    formatPSD            = "PSD (recommended)",
    formatTIFF           = "TIFF",
    formatJPEG           = "JPEG",

    -- Log messages
    logInitStart         = "AutoPortraiture initializing...",
    logInitComplete      = "AutoPortraiture initialized successfully",
    logShutdown          = "AutoPortraiture shutting down...",
    logShutdownComplete  = "AutoPortraiture shutdown complete",
    logSettingsUpdated   = "Settings updated",
    logShortcutsRegistered = "Shortcuts registered (assign in Lightroom -> Edit -> Keyboard Shortcuts)",
    logPrefsMigrated     = "Preferences migration complete (version %s)",
}

return { strings = strings }
