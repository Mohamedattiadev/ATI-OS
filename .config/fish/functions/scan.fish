function scan
    if test (count $argv) -ne 1
        echo "Usage: scan <image_path>"
        return 1
    end

    set img $argv[1]

    # OCR with maximum fidelity
    set ocr_output (tesseract "$img" stdout -l eng+ara --psm 11 2>/dev/null)

    if test -z "$ocr_output"
        echo "❌ OCR failed. Check image/languages."
        notify-send "Scan Failed" "Check image or language settings."
        return 1
    end

    # Copy to clipboard exactly as read
    echo "$ocr_output" | xclip -selection clipboard

    # Desktop notification
    notify-send "OCR Complete" "Text copied to clipboard!"
    echo "✅ OCR text copied to clipboard!"
end
