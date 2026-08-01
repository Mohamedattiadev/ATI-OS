# xprop, with the PID of the window you clicked copied to the clipboard.
#
# The point is the kill loop: you see a misbehaving window, you want its
# process gone, and the number you need is buried in the middle of a 40-line
# property dump. This copies it as you click, so the number is already in the
# clipboard by the time you have read the output.
#
# ONLY the bare, interactive `xprop` is wrapped. With any argument at all
# (`xprop -root`, `xprop -id 0x123`, `xprop WM_CLASS`) this hands straight
# over to the real binary untouched -- those are the scripted uses, they have
# no window to click, and silently changing their behaviour would be a trap.
function xprop --description 'xprop; bare invocation also copies the clicked window PID'
    if test (count $argv) -gt 0
        command xprop $argv
        return $status
    end

    # Captured rather than streamed, because the PID has to be read out of the
    # same dump the user sees. Printed first so the click still feels immediate.
    set -l out (command xprop)
    or return $status
    printf '%s\n' $out

    # -f (filter) prints only the lines that matched, so a window without the
    # property yields an empty list rather than a bogus value.
    set -l pid (printf '%s\n' $out | string replace -rf '^_NET_WM_PID\(CARDINAL\) = ([0-9]+)$' '$1')

    if test -z "$pid"
        # Not every window sets _NET_WM_PID -- it is a convention, not a
        # requirement, and Java/Wine/some GTK dialogs skip it. Say so instead
        # of leaving the last unrelated thing sitting in the clipboard.
        echo "xprop: no _NET_WM_PID on that window — nothing copied" >&2
        return 1
    end

    printf '%s' $pid | xclip -selection clipboard

    # The command that actually uses the number. `kill`, NOT `pkill`: pkill
    # matches a process NAME, so `pkill 4242` looks for a process called
    # "4242", finds nothing, and exits 1 -- while you conclude the PID was
    # wrong. `kill 4242` is the one that takes a PID.
    set -l name (ps -p $pid -o comm= 2>/dev/null)
    echo "PID $pid ($name) copied — kill $pid" >&2
end
