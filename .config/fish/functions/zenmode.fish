function zenmode
    # Check if Qtile is running
    if not pgrep -x qtile >/dev/null
        echo "Qtile not running"
        return 1
    end

    # Python here-doc
    python3 - < < PYTHON
    try:
    from libqtile import qtile
    for s in qtile.screens:
        s.top.toggle_hide()
        print("Zen mode toggled")
        except Exception as e:
        print("Error toggling Zen mode:", e)
        PYTHON
    end
