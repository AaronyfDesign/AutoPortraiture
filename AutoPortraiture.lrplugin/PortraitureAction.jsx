/**
 * AutoPortraiture — Photoshop UXP/ExtendScript
 * PortraitureAction.jsx — Photoshop script: Portraiture plugin call, 5 presets, auto-save
 *
 * Executes within Photoshop to:
 * 1. Open the provided TIFF files
 * 2. Apply Portraiture skin retouching with the selected preset
 * 3. Save as PSD (preserving layers)
 * 4. Close the document
 *
 * Usage (invoked from main.lua):
 *   PortraitureAction.jsx --preset "Medium Smoothing" --smoothing 65 --texture 40 --pores 65 --sharpening 15 --dontDisplay true --file "/path/to/image.tiff"
 */

#target photoshop

// ========================================================================
// Preset definitions (must match main.lua PRESETS table)
// ========================================================================

var PRESETS = {
    "Subtle":           { smoothing: 25, texture: 15, pores: 90, sharpening: 25 },
    "Light Smoothing":  { smoothing: 40, texture: 25, pores: 80, sharpening: 20 },
    "Medium Smoothing": { smoothing: 65, texture: 40, pores: 65, sharpening: 15 },
    "Strong Smoothing": { smoothing: 80, texture: 55, pores: 50, sharpening: 10 },
    "Portrait":         { smoothing: 70, texture: 35, pores: 70, sharpening: 18 },
};

// ========================================================================
// Parse command-line arguments
// ========================================================================

function parseArgs() {
    var args = $.argv;
    var parsed = {
        preset: "Medium Smoothing",
        smoothing: 65,
        texture: 40,
        pores: 65,
        sharpening: 15,
        dontDisplay: true,
        files: [],
    };

    for (var i = 0; i < args.length; i++) {
        switch (args[i]) {
            case "--preset":
                parsed.preset = args[++i];
                break;
            case "--smoothing":
                parsed.smoothing = parseInt(args[++i], 10);
                break;
            case "--texture":
                parsed.texture = parseInt(args[++i], 10);
                break;
            case "--pores":
                parsed.pores = parseInt(args[++i], 10);
                break;
            case "--sharpening":
                parsed.sharpening = parseInt(args[++i], 10);
                break;
            case "--dontDisplay":
                parsed.dontDisplay = (args[++i] === "true");
                break;
            case "--file":
                parsed.files.push(args[++i]);
                break;
        }
    }

    // If preset exists, override individual params
    if (PRESETS[parsed.preset]) {
        var p = PRESETS[parsed.preset];
        parsed.smoothing = p.smoothing;
        parsed.texture = p.texture;
        parsed.pores = p.pores;
        parsed.sharpening = p.sharpening;
    }

    return parsed;
}

// ========================================================================
// Portraiture plugin invocation
// ========================================================================

/**
 * Invokes the Portraiture plugin via Action Manager.
 * Uses the "dontDisplay" mode to suppress UI for batch automation.
 */
function applyPortraiture(params) {
    var desc = new ActionDescriptor();
    var ref = new ActionReference();

    // Reference the Portraiture plugin filter
    ref.putEnumerated(charIDToTypeID("Plg "), charIDToTypeID("Plg "), charIDToTypeID("Portraiture"));
    desc.putReference(charIDToTypeID("null"), ref);

    // Portraiture parameters
    desc.putInteger(charIDToTypeID("Smth"), params.smoothing);      // Skin Smoothing
    desc.putInteger(charIDToTypeID("TxtS"), params.texture);         // Texture Smoothing
    desc.putInteger(charIDToTypeID("Pore"), params.pores);           // Pore Preservation
    desc.putInteger(charIDToTypeID("Shrp"), params.sharpening);      // Sharpening

    // Dont display mode (suppresses Portraiture dialog)
    if (params.dontDisplay) {
        desc.putBoolean(charIDToTypeID("Dont"), true);
    }

    try {
        executeAction(charIDToTypeID("Plg "), desc, DialogModes.NO);
        $.writeln("[AutoPortraiture] Portraiture applied: smoothing=" + params.smoothing +
                  " texture=" + params.texture + " pores=" + params.pores +
                  " sharpening=" + params.sharpening);
    } catch (e) {
        $.writeln("[AutoPortraiture] Portraiture error: " + e.toString());

        // Fallback: try invoking Portraiture via plugin name
        try {
            var portDesc = new ActionDescriptor();
            portDesc.putString(charIDToTypeID("PleN"), "Portraiture");
            portDesc.putInteger(charIDToTypeID("Smth"), params.smoothing);
            portDesc.putInteger(charIDToTypeID("TxtS"), params.texture);
            portDesc.putInteger(charIDToTypeID("Pore"), params.pores);
            portDesc.putInteger(charIDToTypeID("Shrp"), params.sharpening);
            if (params.dontDisplay) {
                portDesc.putBoolean(charIDToTypeID("Dont"), true);
            }
            executeAction(charIDToTypeID("Plg "), portDesc, DialogModes.NO);
            $.writeln("[AutoPortraiture] Portraiture applied (fallback method)");
        } catch (e2) {
            $.writeln("[AutoPortraiture] Portraiture fallback also failed: " + e2.toString());
            throw e2;
        }
    }
}

// ========================================================================
// Apply unsharp mask (sharpening)
// ========================================================================

function applySharpening(amount) {
    var desc = new ActionDescriptor();
    desc.putEnumerated(charIDToTypeID("As  "), charIDToTypeID("As  "), charIDToTypeID("UnsM"));
    desc.putUnitDouble(charIDToTypeID("Amnt"), charIDToTypeID("#Prc"), amount);
    desc.putUnitDouble(charIDToTypeID("Rds "), charIDToTypeID("#Pxl"), 1.0);
    desc.putInteger(charIDToTypeID("Thsh"), 3);
    executeAction(charIDToTypeID("As  "), desc, DialogModes.NO);
}

// ========================================================================
// Save document as PSD
// ========================================================================

function saveAsPSD(doc, filePath) {
    var psdPath = filePath.replace(/\.(tiff?|TIFF?)$/i, ".psd");

    var desc = new ActionDescriptor();
    desc.putPath(charIDToTypeID("In  "), new File(psdPath));

    var psdOpts = new ActionDescriptor();
    psdOpts.putBoolean(charIDToTypeID("Al  "), false);          // Alpha channels
    psdOpts.putBoolean(charIDToTypeID("AnSp"), false);           // Spot colors
    psdOpts.putBoolean(charIDToTypeID("LyrI"), true);            // Layers
    psdOpts.putEnumerated(charIDToTypeID("Encd"), charIDToTypeID("Encd"), charIDToTypeID("raw "));

    desc.putObject(charIDToTypeID("As  "), charIDToTypeID("Pht3"), psdOpts);
    desc.putBoolean(charIDToTypeID("Cpy "), true);                // Copy (keep original open)

    executeAction(charIDToTypeID("save"), desc, DialogModes.NO);
    $.writeln("[AutoPortraiture] Saved PSD: " + psdPath);

    return psdPath;
}

// ========================================================================
// Process a single file
// ========================================================================

function processFile(filePath, params) {
    $.writeln("[AutoPortraiture] Processing: " + filePath);

    // Open the TIFF file
    var file = new File(filePath);
    if (!file.exists) {
        $.writeln("[AutoPortraiture] File not found: " + filePath);
        return null;
    }

    var doc = app.open(file);
    if (!doc) {
        $.writeln("[AutoPortraiture] Failed to open document: " + filePath);
        return null;
    }

    try {
        // Duplicate the background layer for non-destructive editing
        var bgLayer = doc.artLayers.getByName("Background");
        if (bgLayer) {
            bgLayer.duplicate();
        }
    } catch (e) {
        $.writeln("[AutoPortraiture] Could not duplicate background layer: " + e.toString());
    }

    // Apply Portraiture
    try {
        applyPortraiture(params);
    } catch (e) {
        $.writeln("[AutoPortraiture] Portraiture failed, continuing with sharpening only");
    }

    // Apply sharpening
    try {
        applySharpening(params.sharpening);
    } catch (e) {
        $.writeln("[AutoPortraiture] Sharpening failed: " + e.toString());
    }

    // Save as PSD
    var psdPath = saveAsPSD(doc, filePath);

    // Close the document
    doc.close(SaveOptions.DONOTSAVECHANGES);
    $.writeln("[AutoPortraiture] Processing complete for: " + filePath);

    return psdPath;
}

// ========================================================================
// Main entry point
// ========================================================================

function main() {
    var params = parseArgs();

    if (params.files.length === 0) {
        $.writeln("[AutoPortraiture] No files specified. Usage:");
        $.writeln("  PortraitureAction.jsx --preset \"Medium Smoothing\" --file \"/path/to/image.tiff\"");
        return;
    }

    $.writeln("[AutoPortraiture] Starting batch processing: " + params.files.length + " file(s)");
    $.writeln("[AutoPortraiture] Preset: " + params.preset +
              " (smoothing=" + params.smoothing + ", texture=" + params.texture +
              ", pores=" + params.pores + ", sharpening=" + params.sharpening + ")");

    var results = { success: [], failed: [] };

    for (var i = 0; i < params.files.length; i++) {
        try {
            var psdPath = processFile(params.files[i], params);
            if (psdPath) {
                results.success.push(psdPath);
            } else {
                results.failed.push(params.files[i]);
            }
        } catch (e) {
            $.writeln("[AutoPortraiture] Error processing " + params.files[i] + ": " + e.toString());
            results.failed.push(params.files[i]);
        }
    }

    $.writeln("[AutoPortraiture] Batch complete: " + results.success.length + " succeeded, " +
              results.failed.length + " failed");

    // Output results for Lightroom to read
    $.writeln("[AutoPortraiture_RESULT]");
    $.writeln(JSON.stringify(results));
    $.writeln("[/AutoPortraiture_RESULT]");
}

// Run main
main();
