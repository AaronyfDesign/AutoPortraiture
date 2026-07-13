#!/bin/sh
# ============================================================
# AutoPortraiture Export Action for Lightroom Classic
#
# 工作流程：
#   1. LR 导出 JPEG 后，将文件路径作为 $1 传给本脚本
#   2. 脚本通过 AppleScript 调 Photoshop 执行 JSX
#   3. JSX 在 PS 中：打开 JPEG → 调用滤镜 → 另存为 JPEG
#   4. 脚本删除原始 JPEG 和临时 PSD（如有）
#
# 滤镜调用方式：
#   通过 executeAction(stringIDToTypeID(FILTER_ID), ...) 直接调用
#   不依赖预录 Action，更换滤镜只需改 FILTER_ID 配置项
#
# 已知滤镜标识符：
#   Camera Raw Filter  → "AdobeCameraRawFilter"
#   Twirl (旋转扭曲)    → "twirl"
#   Gaussian Blur      → "GaussianBlur"
#   Surface Blur       → "surfaceBlur"
#   Portraiture 3/4    → 需安装后用 ScriptingListener 插件查询
# ============================================================

# ==================== CONFIG ====================
# 滤镜标识符（Photoshop 内部 string ID）
# 更换滤镜只需修改这一行
FILTER_ID="Portraiture 4"

# 滤镜调用时是否显示对话框
# ALL = 显示滤镜界面（可手动调参）
# NO  = 静默执行（用默认参数，不弹窗）
FILTER_DIALOG_MODE="ALL"

# 滤镜对话框弹出后自动点击 OK（适用于 Twirl、Portraiture 等需确认的滤镜）
# yes = 自动点击 OK，批量处理无需手动操作
# no  = 等待手动点击 OK
AUTO_CLICK_OK="yes"

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
OUTPUT_FILE="$DIRNAME/${FILENAME}_processed.jpg"

log "Output: $OUTPUT_FILE"
notify "Processing: $BASENAME..."

JSX_FILE="/tmp/ap_portraiture_$$.jsx"
cat > "$JSX_FILE" << JSXEND
(function() {
    var inputFile = "$INPUT_FILE";
    var outputFile = "$OUTPUT_FILE";
    var jpegQuality = $JPEG_QUALITY;
    var filterId = "$FILTER_ID";
    var dialogMode = "$FILTER_DIALOG_MODE";

    // 禁用 PS 对话框（我们自己控制滤镜对话框）
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

    // --- Step 3: 调用滤镜 ---
    var mode = (dialogMode === "ALL") ? DialogModes.ALL : DialogModes.NO;
    try {
        var filterDesc = new ActionDescriptor();
        try {
            executeAction(stringIDToTypeID(filterId), filterDesc, mode);
            $.writeln("Filter applied (stringID): " + filterId);
        } catch (e1) {
            // 回退：尝试 4 字符 charID
            executeAction(charIDToTypeID(filterId), filterDesc, mode);
            $.writeln("Filter applied (charID): " + filterId);
        }
    } catch (e) {
        $.writeln("Filter failed: " + e.toString());
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

log "JSX script created (filter=$FILTER_ID)"

# 创建 AppleScript 启动文件
ASCPT_FILE="/tmp/ap_launch_$$.scpt"
python3 -c "
scpt = 'tell application \"Adobe Photoshop 2026\"\n'
scpt += '  activate\n'
scpt += '  set jsCode to (read POSIX file \"$JSX_FILE\" as \u00abclass utf8\u00bb)\n'
scpt += '  do javascript jsCode\n'
scpt += 'end tell\n'
with open('$ASCPT_FILE', 'w') as f:
    f.write(scpt)
"

# --- 自动点击滤镜对话框 OK 按钮 ---
# 当 FILTER_DIALOG_MODE=ALL 且 AUTO_CLICK_OK=yes 时
# 滤镜对话框弹出会阻塞 JSX 执行，此后台进程用 System Events
# 轮询检测对话框并自动点击 OK，使流程继续
AUTO_CLICK_PID=""
if [ "$FILTER_DIALOG_MODE" = "ALL" ] && [ "$AUTO_CLICK_OK" = "yes" ]; then
    (
        for i in $(seq 1 60); do
            sleep 0.5
            RESULT=$(osascript -e '
            tell application "System Events"
                tell process "Adobe Photoshop 2025"
                    repeat with w in (every window)
                        try
                            click button "OK" of w
                            return "clicked"
                        end try
                        try
                            click button "确定" of w
                            return "clicked"
                        end try
                    end repeat
                end tell
            end tell
            return "no_dialog"' 2>/dev/null)
            if [ "$RESULT" = "clicked" ]; then
                break
            fi
        done
    ) &
    AUTO_CLICK_PID=$!
    log "Auto-clicker started (PID=$AUTO_CLICK_PID)"
fi

log "Launching Photoshop..."
osascript "$ASCPT_FILE" 2>> "$LOGFILE"
PS_RESULT=$?
log "Photoshop exit code: $PS_RESULT"

# 清理后台自动点击进程
if [ -n "$AUTO_CLICK_PID" ]; then
    kill $AUTO_CLICK_PID 2>/dev/null
    log "Auto-clicker stopped"
fi

if [ -f "$OUTPUT_FILE" ]; then
    OUT_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
    SIZE_MB=$((OUT_SIZE / 1048576))
    log "SUCCESS: ${SIZE_MB}MB: $OUTPUT_FILE"
    notify "Done! ${SIZE_MB}MB: ${FILENAME}_processed.jpg"
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
