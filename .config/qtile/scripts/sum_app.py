def toggle_or_spawn_sum(qtile, myTerm, sum_file):
    title = "sum.md"

    for group in qtile.groups:
        for win in group.windows:
            if title in (win.name or "").lower():

                # 🚀 CASE 1: window is on another workspace
                if win.group != qtile.current_group:
                    win.togroup(qtile.current_group.name)
                    win.toggle_minimize() if win.minimized else None
                    win.focus()
                    win.bring_to_front()

                    if hasattr(win, "toggle_sticky") and not win.sticky:
                        win.toggle_sticky()

                    return  # ⬅️ HARD STOP (no toggle logic)

                # 🚀 CASE 2: same workspace
                if win.minimized:
                    win.toggle_minimize()
                    win.focus()

                elif qtile.current_window != win:
                    win.focus()

                else:
                    # focused → minimize
                    win.toggle_minimize()
                    return

                if hasattr(win, "toggle_sticky") and not win.sticky:
                    win.toggle_sticky()

                win.bring_to_front()
                return

    # 🚀 CASE 3: not running
    qtile.cmd_spawn(
        f"{myTerm} --title sum.md -e nvim -c':set nonumber norelativenumber' {sum_file}"
    )

