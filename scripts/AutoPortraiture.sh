#!/bin/sh
# ============================================================
# AutoPortraiture Export Action for Lightroom Classic
#
# 工作流程：
#   1. LR 导出 JPEG 后，将文件路径作为 $1 传给本脚本
#   2. 脚本通过 AppleScript 调 Photoshop 执行 JSX
#   3. JSX 在 PS 中：打开 JPEG → 回放 Action → 另存为 JPEG
#   4. 脚本删除原始 JPEG 和临时 PSD（如有）
#
# 滤镜调用方式：
#   通过 app.doAction(actionName, actionSet) 回放预录的 PS Action
#   需要先在 PS 中录制一个包含 Portraiture 步骤的 Action
#
# 录制 Action 步骤：
#   1. PS 中打开任意照片
#   2. 窗口 → 动作，新建 Action（命名如 "Portraiture"），放入 Action Set（如 "AutoPortraiture"）
#   3. 开始录制
#   4. 滤镜 → Imagenomic → Portraiture 3/4
#   5. 调整参数，点确定
#   6. 停止录制
# ============================================================

# ==================== CONFIG ====================
# Action 名称和 Action Set 名称（需与 PS 中录制的一致）
ACTION_NAME="Portraiture"
ACTION_SET="AutoPortraiture"

# Photoshop 版本（已测试：2024、2025、2026，其余版本未测试）
PS_VERSION="2025"

# 输出 JPEG 质量 (1-12, 12 = 最高)
JPEG_QUALITY=12
# ================================================

INPUT_FILE="$1"
LOGFILE="$HOME/Desktop/autoportraiture.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$LOGFILE"
}

notify() {
    osascript -e "display notification \"$1\" with title \"AutoPortraiture\" $2" 2>/dev/null
}

log "=== Export Action called ==="
log "Input: $INPUT_FILE"

if [ -z "$INPUT_FILE" ]; then
    log "ERROR: No input file provided"
    notify "Error: No input file"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    log "ERROR: File not found: $INPUT_FILE"
    notify "Error: File not found"
    exit 1
fi

BASENAME=$(basename "$INPUT_FILE")
FILENAME="${BASENAME%.*}"
DIRNAME=$(dirname "$INPUT_FILE")
OUTPUT_FILE="$DIRNAME/${FILENAME}_${ACTION_NAME}.jpg"

log "Output: $OUTPUT_FILE"
notify "Processing: $BASENAME..."

JSX_FILE="/tmp/ap_portraiture_$$.jsx"
cat > "$JSX_FILE" << JSXEND
(function() {
    var inputFile = "$INPUT_FILE";
    var outputFile = "$OUTPUT_FILE";
    var jpegQuality = $JPEG_QUALITY;
    var actionName = "$ACTION_NAME";
    var actionSet = "$ACTION_SET";

    // 禁用所有 PS 对话框
    app.displayDialogs = DialogModes.NO;

    // --- Step 1: 打开文件 ---
    var file = new File(inputFile);
    if (!file.exists) {
        $.writeln("ERROR: File not found: " + inputFile);
        return;
    }
    var doc = app.open(file);
    if (!doc) {
        $.writeln("ERROR: Failed to open document");
        return;
    }
    $.writeln("Opened: " + inputFile);

    // --- Step 2: 复制背景图层 ---
    try {
        var bgLayer = doc.artLayers.getByName("Background");
        if (bgLayer) bgLayer.duplicate();
    } catch (e) {}

    // --- Step 3: 回放 Action（调用 Portraiture） ---
    try {
        app.doAction(actionName, actionSet);
        $.writeln("Action applied: " + actionSet + "/" + actionName);
    } catch (e) {
        $.writeln("Action failed: " + e.toString());
    }

    // --- Step 4: 合并图层 ---
    doc.flatten();

    // --- Step 5: 另存为 JPEG ---
    var outFile = new File(outputFile);
    var jpegOpts = new JPEGSaveOptions();
    jpegOpts.quality = jpegQuality;
    jpegOpts.matte = MatteType.NONE;
    doc.saveAs(outFile, jpegOpts, true, Extension.LOWERCASE);
    $.writeln("Saved: " + outputFile);

    // --- Step 6: 关闭文档 ---
    doc.close(SaveOptions.DONOTSAVECHANGES);

    app.displayDialogs = DialogModes.ALL;
    $.writeln("AutoPortraiture: Done");
})();
JSXEND

log "JSX script created (action=$ACTION_SET/$ACTION_NAME)"

# 创建 AppleScript 启动文件
ASCPT_FILE="/tmp/ap_launch_$$.scpt"
python3 -c "
scpt = 'tell application \"Adobe Photoshop $PS_VERSION\"\n'
scpt += '  activate\n'
scpt += '  set jsCode to (read POSIX file \"$JSX_FILE\" as \u00abclass utf8\u00bb)\n'
scpt += '  do javascript jsCode\n'
scpt += 'end tell\n'
with open('$ASCPT_FILE', 'w') as f:
    f.write(scpt)
"

log "Launching Photoshop (PS $PS_VERSION)..."
osascript "$ASCPT_FILE" 2>> "$LOGFILE"
PS_RESULT=$?
log "Photoshop exit code: $PS_RESULT"

if [ -f "$OUTPUT_FILE" ]; then
    OUT_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    SIZE_MB=$((OUT_SIZE / 1048576))
    log "SUCCESS: ${SIZE_MB}MB: $OUTPUT_FILE"
    notify "Done! ${SIZE_MB}MB: ${FILENAME}_${ACTION_NAME}.jpg"
else
    log "ERROR: Output not found"
    notify "Error: Output file not created"
fi

# 删除原始 JPEG
rm -f "$INPUT_FILE"
log "Deleted original: $INPUT_FILE"

# 删除临时 PSD
PSD_FILE="$DIRNAME/${FILENAME}.psd"
if [ -f "$PSD_FILE" ]; then
    rm -f "$PSD_FILE"
    log "Deleted temp PSD: $PSD_FILE"
fi

rm -f "$JSX_FILE" "$ASCPT_FILE"
log "=== Done ==="
