--[[
    AutoPortraiture - Lightroom SDK Plugin
    PostProcess.lua - Post-processing: file monitoring, re-import to Lightroom, stacking

    After Photoshop completes Portraiture processing:
    1. Monitor for PSD output files (file size stability check)
    2. Re-import processed PSD files into Lightroom catalog
    3. Stack with original photos (optional)
]]

local LrApplication       = import 'LrApplication'
local LrDate              = import 'LrDate'
local LrFileUtils         = import 'LrFileUtils'
local LrFunctionContext   = import 'LrFunctionContext'
local LrLogger            = import 'LrLogger'
local LrPathUtils         = import 'LrPathUtils'
local LrPrefs             = import 'LrPrefs'
local LrProgressScope     = import 'LrProgressScope'
local LrTasks             = import 'LrTasks'
local LrDialogs           = import 'LrDialogs'

local logger = LrLogger('AutoPortraiture')

-- Safely get prefs
local prefs = {}
local ok, p = pcall(function() return LrPrefs.prefsForPlugin() end)
if ok then prefs = p or {} end

local M = {}  -- module table

-- ========================================================================
-- File size stability check
-- ========================================================================

local function isFileStable(filePath, interval, maxRetries)
    interval = interval or (prefs.fileStabilityInterval or 2)
    maxRetries = maxRetries or 30

    local prevSize = -1
    for i = 1, maxRetries do
        local currentSize
        local attrOk, attrs = pcall(function() return LrFileUtils.fileAttributes(filePath) end)
        if attrOk and attrs then
            currentSize = attrs.fileSize
        end
        if currentSize and currentSize > 0 and currentSize == prevSize then
            logger:info("File stable: " .. filePath .. " (" .. currentSize .. " bytes)")
            return true
        end
        prevSize = currentSize or -1
        LrTasks.sleep(interval)
    end

    logger:warn("File stability check timed out for: " .. filePath)
    return false
end

-- ========================================================================
-- Convert TIFF path to expected PSD path
-- ========================================================================

local function getExpectedPSDPath(tiffPath)
    local psdPath = string.gsub(tiffPath, "%.tiff$", ".psd")
    psdPath = string.gsub(psdPath, "%.tif$", ".psd")
    return psdPath
end

-- ========================================================================
-- Monitor for PSD output files
-- ========================================================================

local function waitForPSDFiles(tiffPaths, timeout)
    timeout = timeout or (prefs.psTimeout or 120)
    local startTime = LrDate.currentTime()

    local psdPaths = {}

    for _, tiffPath in ipairs(tiffPaths) do
        local psdPath = getExpectedPSDPath(tiffPath)
        logger:info("Waiting for PSD: " .. psdPath)

        while true do
            local elapsed = LrDate.currentTime() - startTime
            if elapsed > timeout then
                logger:error("Timeout waiting for PSD: " .. psdPath)
                break
            end

            if LrFileUtils.exists(psdPath) then
                if prefs.waitForFileStability ~= false then
                    if isFileStable(psdPath) then
                        table.insert(psdPaths, psdPath)
                        break
                    end
                else
                    table.insert(psdPaths, psdPath)
                    break
                end
            end

            LrTasks.sleep(2)
        end
    end

    return psdPaths
end

-- ========================================================================
-- Re-import PSD files into Lightroom catalog
-- ========================================================================

local function reimportPSDFiles(catalog, psdPaths, originalPhotos)
    local progress = LrProgressScope({
        title = "Re-importing retouched photos...",
    })

    local numFiles = #psdPaths
    local importedPhotos = {}

    for i, psdPath in ipairs(psdPaths) do
        progress:setPortionComplete(i - 1, numFiles)
        progress:setCaption("Importing " .. LrPathUtils.leafName(psdPath) ..
                            " (" .. i .. "/" .. numFiles .. ")")

        local success, result = LrTasks.pcall(function()
            catalog:withWriteAccessDo("import PSD", function()
                local original = originalPhotos[i]
                local importedPhoto = catalog:addPhoto(psdPath, original, 'below')
                if importedPhoto then
                    table.insert(importedPhotos, importedPhoto)
                    logger:info("Re-imported: " .. psdPath)
                end
            end)
        end)

        if not success then
            logger:error("Failed to import " .. psdPath .. ": " .. tostring(result))
        end
    end

    progress:done()

    -- Match imported photos with originals for stacking
    if prefs.stackWithOriginal ~= false and #importedPhotos > 0 then
        M.stackWithOriginals(catalog, importedPhotos, originalPhotos)
    end

    return importedPhotos
end

-- ========================================================================
-- Stack imported photos with originals
-- ========================================================================

function M.stackWithOriginals(catalog, importedPhotos, originalPhotos)
    logger:info("Stacking " .. #importedPhotos .. " photos with originals")

    -- addPhoto already stacks with original when stackWithPhoto is provided,
    -- so this function is now a no-op. Kept for compatibility.
end

-- ========================================================================
-- Clean up temporary TIFF files
-- ========================================================================

local function cleanupTempFiles(tiffPaths)
    for _, tiffPath in ipairs(tiffPaths) do
        local success, err = pcall(function()
            if LrFileUtils.exists(tiffPath) then
                LrFileUtils.delete(tiffPath)
                logger:info("Cleaned up temp file: " .. tiffPath)
            end
        end)
        if not success then
            logger:warn("Could not delete temp file " .. tiffPath .. ": " .. tostring(err))
        end
    end
end

-- ========================================================================
-- Main: monitor and reimport (called from main.lua)
-- ========================================================================

function M.monitorAndReimport(tiffPaths, exportDir, originalPhotos)
    LrTasks.startAsyncTask(function()

        logger:info("PostProcess: monitoring for " .. #tiffPaths .. " PSD file(s)")

        -- Step 1: Wait for all PSD files to appear
        local psdPaths = waitForPSDFiles(tiffPaths)

        if #psdPaths == 0 then
            LrDialogs.showMessage("AutoPortraiture", "No PSD files were produced by Photoshop. " ..
                                "Check that Portraiture is installed and functioning.")
            return
        end

        logger:info("All " .. #psdPaths .. " PSD file(s) found")

        -- Step 2: Re-import PSD files into Lightroom
        local catalog = LrApplication.activeCatalog()
        local importedPhotos = reimportPSDFiles(catalog, psdPaths, originalPhotos)

        -- Step 3: Clean up temporary TIFF files
        cleanupTempFiles(tiffPaths)

        -- Step 4: Show completion notification
        local message = string.format(
            "AutoPortraiture complete: %d photo(s) retouched and imported.",
            #importedPhotos
        )
        LrDialogs.showBezel(message)
        logger:info(message)

    end)
end

return M
