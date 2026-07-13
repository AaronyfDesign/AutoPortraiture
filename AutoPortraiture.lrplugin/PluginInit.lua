--[[
    AutoPortraiture - Lightroom SDK Plugin
    PluginInit.lua - Plugin info provider for Plugin Manager

    This file is loaded by Lightroom at plugin load time via LrPluginInfoProvider.
    It MUST return a table with sectionsForTopOfDialog(f, properties).
    No side effects or initialization should run at module load time.
]]

local LrBinding           = import 'LrBinding'
local LrDialogs           = import 'LrDialogs'
local LrFunctionContext   = import 'LrFunctionContext'
local LrLogger            = import 'LrLogger'
local LrPrefs             = import 'LrPrefs'
local LrView              = import 'LrView'

local logger = LrLogger('AutoPortraiture')

local PLUGIN_VERSION = "1.2.0"

-- Safely get prefs (wrapped in pcall in case prefs access fails)
local prefs = {}
local ok, p = pcall(function() return LrPrefs.prefsForPlugin() end)
if ok then prefs = p or {} end

-- ========================================================================
-- Default preferences
-- ========================================================================

local DEFAULT_PREFS = {
    preset              = "Medium Smoothing",
    outputFormat        = "PSD",
    outputBitDepth      = 16,
    psTimeout           = 120,
    waitForFileStability = true,
    fileStabilityInterval = 2,
    stackWithOriginal   = true,
    debugLogging        = false,
    dontDisplayPortraiture = true,
}

-- ========================================================================
-- Settings dialog (shown when user clicks "Settings" in Plugin Manager)
-- ========================================================================

local function showSettingsDialog()
    LrFunctionContext.callWithContext("AutoPortraiture.settings", function(context)

        local f = LrView.osFactory()
        local props = LrBinding.makePropertyTable(context)

        -- Load current values from prefs, falling back to defaults
        props.preset                = prefs.preset or DEFAULT_PREFS.preset
        props.outputFormat          = prefs.outputFormat or DEFAULT_PREFS.outputFormat
        props.psTimeout             = prefs.psTimeout or DEFAULT_PREFS.psTimeout
        props.fileStabilityInterval = prefs.fileStabilityInterval or DEFAULT_PREFS.fileStabilityInterval
        props.stackWithOriginal     = prefs.stackWithOriginal ~= false
        props.waitForFileStability  = prefs.waitForFileStability ~= false
        props.debugLogging          = prefs.debugLogging or false
        props.dontDisplayPortraiture = prefs.dontDisplayPortraiture ~= false

        local bind = LrView.bind

        local contents = f:column {
            spacing = 12,
            fill_horizontal = 1,

            -- Info header
            f:column {
                spacing = 4,
                f:static_text {
                    title = "AutoPortraiture v" .. PLUGIN_VERSION,
                    font = "<system/bold>",
                },
                f:static_text {
                    title = "One-click skin retouching: Lightroom -> Photoshop -> Portraiture -> Lightroom",
                },
            },

            f:separator { fill_horizontal = 1 },

            -- Preset selection
            f:row {
                spacing = 8,
                f:static_text {
                    title = "Retouching Preset",
                    alignment = "right",
                    width = LrView.share "label_width",
                },
                f:popup_menu {
                    items = {
                        { title = "Subtle" },
                        { title = "Light Smoothing" },
                        { title = "Medium Smoothing" },
                        { title = "Strong Smoothing" },
                        { title = "Portrait" },
                    },
                    value = bind("preset"),
                },
            },

            -- Output format
            f:row {
                spacing = 8,
                f:static_text {
                    title = "Output Format",
                    alignment = "right",
                    width = LrView.share "label_width",
                },
                f:popup_menu {
                    items = {
                        { title = "PSD (recommended)" },
                        { title = "TIFF" },
                        { title = "JPEG" },
                    },
                    value = bind("outputFormat"),
                },
            },

            -- Timeout slider
            f:row {
                spacing = 8,
                f:static_text {
                    title = "Photoshop Timeout (sec)",
                    alignment = "right",
                    width = LrView.share "label_width",
                },
                f:slider {
                    value = bind("psTimeout"),
                    min = 30,
                    max = 600,
                    integral = true,
                },
                f:static_text {
                    title = bind {
                        key = "psTimeout",
                        transform = function(v) return tostring(v) .. "s" end,
                    },
                },
            },

            -- File stability interval
            f:row {
                spacing = 8,
                f:static_text {
                    title = "File Stability Check (sec)",
                    alignment = "right",
                    width = LrView.share "label_width",
                },
                f:slider {
                    value = bind("fileStabilityInterval"),
                    min = 1,
                    max = 10,
                    integral = true,
                },
                f:static_text {
                    title = bind {
                        key = "fileStabilityInterval",
                        transform = function(v) return tostring(v) .. "s" end,
                    },
                },
            },

            -- Checkboxes
            f:column {
                spacing = 6,
                f:checkbox {
                    title = "Stack retouched photos with originals",
                    value = bind("stackWithOriginal"),
                },
                f:checkbox {
                    title = "Wait for file size stability before re-import",
                    value = bind("waitForFileStability"),
                },
                f:checkbox {
                    title = "Suppress Portraiture dialog (dontDisplay mode)",
                    value = bind("dontDisplayPortraiture"),
                },
                f:checkbox {
                    title = "Enable debug logging",
                    value = bind("debugLogging"),
                },
            },
        }

        local result = LrDialogs.presentModalDialog({
            title = "AutoPortraiture Settings",
            contents = contents,
            actionVerb = "Save",
            cancelVerb = "Cancel",
        })

        if result == "ok" then
            -- Normalize output format (strip parenthetical description)
            local fmt = props.outputFormat or "PSD"
            if string.find(fmt, "PSD") then fmt = "PSD" end
            if string.find(fmt, "TIFF") then fmt = "TIFF" end
            if string.find(fmt, "JPEG") then fmt = "JPEG" end

            prefs.preset                = props.preset
            prefs.outputFormat          = fmt
            prefs.psTimeout             = props.psTimeout
            prefs.fileStabilityInterval = props.fileStabilityInterval
            prefs.waitForFileStability  = props.waitForFileStability
            prefs.stackWithOriginal     = props.stackWithOriginal
            prefs.debugLogging          = props.debugLogging
            prefs.dontDisplayPortraiture = props.dontDisplayPortraiture

            pcall(function()
                logger:info("Settings saved: preset=" .. tostring(prefs.preset) ..
                           " format=" .. tostring(prefs.outputFormat) ..
                           " timeout=" .. tostring(prefs.psTimeout))
            end)
            LrDialogs.showBezel("AutoPortraiture settings saved", true)
        end
    end)
end

-- ========================================================================
-- Plugin Manager info section (shown in Plugin Manager main view)
-- ========================================================================

local function sectionsForTopOfDialog(f, properties)
    return {
        {
            title = "AutoPortraiture",
            synopsis = "One-click retouching workflow",
            f:column {
                spacing = 8,
                f:static_text {
                    title = "Version: " .. PLUGIN_VERSION,
                },
                f:static_text {
                    title = "One-click skin retouching: Lightroom -> Photoshop -> Portraiture -> Lightroom",
                },
                f:static_text {
                    title = "Click 'Settings' to configure presets, output format, and processing options.",
                },
            },
        },
    }
end

-- ========================================================================
-- Return the plugin info provider table
-- This MUST be reached without any errors at module load time.
-- ========================================================================

return {
    sectionsForTopOfDialog = sectionsForTopOfDialog,
    processSettingsDialog = showSettingsDialog,
}
