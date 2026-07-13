--[[
    AutoPortraiture - Lightroom SDK Plugin
    main.lua - Core workflow: export TIFF, launch Photoshop, monitor PSD, re-import

    Workflow: Lightroom -> Photoshop -> Portraiture -> Lightroom
]]

-- ========================================================================
-- Imports
-- ========================================================================

local LrApplication       = import 'LrApplication'
local LrDate              = import 'LrDate'
local LrDialogs           = import 'LrDialogs'
local LrFileUtils         = import 'LrFileUtils'
local LrFunctionContext   = import 'LrFunctionContext'
local LrLogger            = import 'LrLogger'
local LrPathUtils         = import 'LrPathUtils'
local LrPrefs             = import 'LrPrefs'
local LrProgressScope     = import 'LrProgressScope'
local LrTasks             = import 'LrTasks'
local LrExportSession     = import 'LrExportSession'

-- ========================================================================
-- Logger
-- ========================================================================

local logger = LrLogger('AutoPortraiture')
logger:enable('logfile')

-- ========================================================================
-- Preferences (safe access)
-- ========================================================================

local prefs = {}
local okPrefs, p = pcall(function() return LrPrefs.prefsForPlugin() end)
if okPrefs and p then prefs = p end

-- ========================================================================
-- Presets (must match PortraitureAction.jsx)
-- ========================================================================

local PRESETS = {
    ["Subtle"]           = { smoothing = 25, texture = 15, pores = 90, sharpening = 25 },
    ["Light Smoothing"]  = { smoothing = 40, texture = 25, pores = 80, sharpening = 20 },
    ["Medium Smoothing"] = { smoothing = 65, texture = 40, pores = 65, sharpening = 15 },
    ["Strong Smoothing"] = { smoothing = 80, texture = 55, pores = 50, sharpening = 10 },
    ["Portrait"]         = { smoothing = 70, texture = 35, pores = 70, sharpening = 18 },
}

-- ========================================================================
-- Plugin directory
-- ========================================================================

local pluginDir = _PLUGIN.path

-- ========================================================================
-- Get selected photos from catalog
-- ========================================================================

local function getSelectedPhotos()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    return photos
end

-- ========================================================================
-- Export photos as 16-bit TIFF
-- ========================================================================

local function exportToTIFF(photos, exportDir)
    local exportSettings = {
        LR_format                  = "TIFF",
        LR_bitDepth                = 16,
        LR_colorSpace              = "ProPhoto",
        LR_export_destinationType  = "specificFolder",
        LR_export_destinationPathPrefix = exportDir,
        LR_export_destinationFolderSuffix = "",
        LR_export_useSubfolder     = false,
        LR_export_overwrite        = true,
        LR_size_doConstrain        = false,
        LR_outputSharpening        = false,
        LR_tokens                  = "{file_name}",
    }

    logger:info("Creating export session for " .. #photos .. " photo(s) to " .. exportDir)

    local exportSession = LrExportSession({
        photosToExport = photos,
        exportSettings = exportSettings,
    })

    -- doExportOnNewTask starts export in a new async task.
    -- It is safe to call from any context and returns immediately.
    -- We then poll the output directory until files appear.
    local numRenditions = exportSession:countRenditions()
    logger:info("Export session created, expecting " .. numRenditions .. " rendition(s)")

    exportSession:doExportOnNewTask()

    -- Wait for export to complete by polling the directory
    local exportedPaths = {}
    local startTime = LrDate.currentTime()
    local timeout = 120  -- 2 minutes max

    while (LrDate.currentTime() - startTime) < timeout do
        -- Use LrFileUtils.files() iterator to scan directory
        local scanOk = pcall(function()
            for filePath in LrFileUtils.files(exportDir) do
                local ext = string.lower(LrPathUtils.extension(filePath))
                if ext == "tif" or ext == "tiff" then
                    -- Check if already in list
                    local alreadyFound = false
                    for _, existing in ipairs(exportedPaths) do
                        if existing == filePath then
                            alreadyFound = true
                            break
                        end
                    end
                    if not alreadyFound then
                        table.insert(exportedPaths, filePath)
                        logger:info("Found exported TIFF: " .. filePath)
                    end
                end
            end
        end)

        -- Check if we have all expected files
        if #exportedPaths >= numRenditions then
            -- Verify file sizes are stable (export complete)
            local allStable = true
            local sizes = {}
            for _, p in ipairs(exportedPaths) do
                local ok2, attrs = pcall(function() return LrFileUtils.fileAttributes(p) end)
                if ok2 and attrs then
                    sizes[p] = attrs.fileSize
                end
            end
            LrTasks.sleep(1)
            for _, p in ipairs(exportedPaths) do
                local ok2, attrs = pcall(function() return LrFileUtils.fileAttributes(p) end)
                if ok2 and attrs then
                    if sizes[p] ~= attrs.fileSize then
                        allStable = false
                    end
                end
            end
            if allStable then
                logger:info("All files exported and stable")
                break
            end
        end

        LrTasks.sleep(1)
    end

    logger:info("Export complete: " .. #exportedPaths .. " file(s)")
    return exportedPaths
end

-- ========================================================================
-- Create wrapper JSX script with embedded arguments
-- ========================================================================

local function createWrapperScript(tiffPaths, preset)
    local p = PRESETS[preset] or PRESETS["Medium Smoothing"]
    local dontDisplay = prefs.dontDisplayPortraiture ~= false

    -- Build the argument array
    local argParts = {}
    table.insert(argParts, '"--preset"')
    table.insert(argParts, '"' .. preset .. '"')
    table.insert(argParts, '"--smoothing"')
    table.insert(argParts, tostring(p.smoothing))
    table.insert(argParts, '"--texture"')
    table.insert(argParts, tostring(p.texture))
    table.insert(argParts, '"--pores"')
    table.insert(argParts, tostring(p.pores))
    table.insert(argParts, '"--sharpening"')
    table.insert(argParts, tostring(p.sharpening))
    table.insert(argParts, '"--dontDisplay"')
    table.insert(argParts, tostring(dontDisplay))

    for _, tiffPath in ipairs(tiffPaths) do
        table.insert(argParts, '"--file"')
        table.insert(argParts, '"' .. tiffPath .. '"')
    end

    local argsStr = table.concat(argParts, ", ")

    -- Read the PortraitureAction.jsx content
    local jsxPath = LrPathUtils.child(pluginDir, "PortraitureAction.jsx")
    local jsxContent = ""
    local ok, content = pcall(function() return LrFileUtils.readFile(jsxPath) end)
    if ok then
        jsxContent = content
    else
        logger:error("Failed to read PortraitureAction.jsx: " .. tostring(content))
        return nil
    end

    -- Create wrapper: set $.argv then run the script
    local wrapper = "// AutoPortraiture wrapper - generated by main.lua\n"
    wrapper = wrapper .. "$.argv = [" .. argsStr .. "];\n"
    wrapper = wrapper .. jsxContent

    -- Write to temp file using standard Lua io
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local wrapperPath = LrPathUtils.child(tempDir, "ap_wrapper_" .. tostring(LrDate.currentTime()) .. ".jsx")

    local file = io.open(wrapperPath, "w")
    if not file then
        logger:error("Failed to open wrapper script for writing: " .. wrapperPath)
        return nil
    end
    file:write(wrapper)
    file:close()

    logger:info("Wrapper script written: " .. wrapperPath)
    return wrapperPath
end

-- ========================================================================
-- Launch Photoshop and execute JSX script
-- ========================================================================

local function launchPhotoshop(jsxPath)
    logger:info("Launching Photoshop with script: " .. jsxPath)

    -- Write an AppleScript file that reads the JSX and executes it in Photoshop.
    -- We use a file because multi-line AppleScript cannot be passed via -e flags.
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local scptPath = LrPathUtils.child(tempDir, "ap_launch_" .. tostring(LrDate.currentTime()) .. ".scpt")

    local scpt = 'tell application "Adobe Photoshop 2025"\n'
    scpt = scpt .. '  activate\n'
    scpt = scpt .. '  set jsCode to (read POSIX file "' .. jsxPath .. '" as ' .. '\194\171' .. 'class utf8' .. '\194\187' .. ')\n'
    scpt = scpt .. '  do javascript jsCode\n'
    scpt = scpt .. 'end tell\n'

    local file = io.open(scptPath, "w")
    if not file then
        logger:error("Failed to write AppleScript launcher")
        return false
    end
    file:write(scpt)
    file:close()

    local cmd = 'osascript "' .. scptPath .. '"'
    logger:info("Command: " .. cmd)

    -- LrTasks.execute must be called from an async task that can yield.
    local result = LrTasks.execute(cmd)
    logger:info("Photoshop command executed, result: " .. tostring(result))

    -- Clean up the AppleScript file
    pcall(function() return LrFileUtils.delete(scptPath) end)

    return true
end

-- ========================================================================
-- Main retouch workflow
-- ========================================================================

local function executeRetouch(isBatch)
    logger:info("=== AutoPortraiture starting (batch=" .. tostring(isBatch) .. ") ===")

    -- Step 1: Get selected photos
    local photos = getSelectedPhotos()

    if #photos == 0 then
        LrDialogs.showMessage(
            "AutoPortraiture",
            "No photos selected. Please select one or more photos in Lightroom before running AutoPortraiture."
        )
        return
    end

    logger:info("Selected " .. #photos .. " photo(s)")

    if #photos > 1 and not isBatch then
        LrDialogs.showMessage(
            "AutoPortraiture",
            "Multiple photos selected. Use 'Batch Retouch' for multiple photos, or select a single photo."
        )
        return
    end

    -- Step 2: Show progress (no functionContext needed when in async task)
    local progress = LrProgressScope({
        title = "AutoPortraiture: Exporting photos as TIFF...",
    })

    -- Step 3: Create export directory
    local tempDir = LrPathUtils.getStandardFilePath("temp")
    local exportDir = LrPathUtils.child(tempDir, "AutoPortraiture_" .. tostring(LrDate.currentTime()))
    local okMkdir = pcall(function() return LrFileUtils.createDirectory(exportDir) end)
    if not okMkdir then
        logger:error("Failed to create export directory: " .. exportDir)
        LrDialogs.showMessage("AutoPortraiture", "Failed to create temporary export directory.")
        progress:done()
        return
    end

    logger:info("Export directory: " .. exportDir)

    -- Step 4: Export photos as 16-bit TIFF
    progress:setCaption("Exporting " .. #photos .. " photo(s) as TIFF...")
    local tiffPaths = exportToTIFF(photos, exportDir)

    if #tiffPaths == 0 then
        logger:error("No TIFF files exported")
        LrDialogs.showMessage("AutoPortraiture", "Failed to export photos as TIFF. Check the log for details.")
        progress:done()
        return
    end

    logger:info("Exported " .. #tiffPaths .. " TIFF file(s)")

    -- Step 5: Create wrapper JSX script
    progress:setCaption("Preparing Photoshop script...")
    local preset = prefs.preset or "Medium Smoothing"
    local wrapperPath = createWrapperScript(tiffPaths, preset)

    if not wrapperPath then
        LrDialogs.showMessage("AutoPortraiture", "Failed to create Photoshop script wrapper.")
        progress:done()
        return
    end

    -- Step 6: Launch Photoshop
    progress:setCaption("Launching Photoshop...")
    progress:setPortionComplete(0.5, 1.0)

    launchPhotoshop(wrapperPath)

    -- Step 7: Start post-processing (monitor for PSD files, re-import)
    progress:setCaption("Waiting for Photoshop to complete...")
    progress:setPortionComplete(0.6, 1.0)

    local postProcessOk, postProcess = pcall(function() return require("PostProcess") end)
    if postProcessOk and postProcess then
        logger:info("PostProcess module loaded, starting monitor")
        progress:done()
        postProcess.monitorAndReimport(tiffPaths, exportDir, photos)
    else
        logger:error("Failed to load PostProcess module: " .. tostring(postProcess))
        progress:done()
        LrDialogs.message(
            "AutoPortraiture",
            "Photoshop has been launched, but the automatic re-import module failed to load. " ..
            "You will need to manually import the processed PSD files from: " .. exportDir
        )
    end

    -- Clean up wrapper script after a delay
    LrTasks.startAsyncTask(function()
        LrTasks.sleep(30)
        pcall(function() return LrFileUtils.delete(wrapperPath) end)
        logger:info("Cleaned up wrapper script")
    end)

    logger:info("=== AutoPortraiture workflow initiated ===")
end

-- ========================================================================
-- Entry point - called by Lightroom when menu item is clicked
-- ========================================================================

-- Menu item clicks run on the main UI thread.
-- Export operations (doExportOnRender) must run in an async task.
local function main()
    local photos = getSelectedPhotos()
    local isBatch = #photos > 1

    LrTasks.startAsyncTask(function()
        executeRetouch(isBatch)
    end)
end

-- Run main
main()
