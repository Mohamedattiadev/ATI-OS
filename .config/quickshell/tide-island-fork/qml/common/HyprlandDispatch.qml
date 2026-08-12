pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland

//
// FORK — every dispatcher in this file was rewritten.
//
// Upstream emits Hyprland's LUA dispatch API:
//
//     hl.dsp.focus({ workspace = 3 })
//     hl.dsp.window.move({ workspace = 5, follow = false, window = "address:0x…" })
//
// **Hyprland 0.56.2 does not have it**, and the failure is silent from the
// user's side — the island's own log is the only place it shows:
//
//     Dispatch request "hl.dsp.focus({ workspace = 3 })"
//         failed with error "Invalid dispatcher"
//
// So clicking a workspace on the island did nothing, and had never done
// anything under this compositor. Same for focusing and closing a window
// from the overview. Found by reading the log while checking something
// else, which is the only way it was ever going to be found: nothing
// throws, nothing is drawn wrong, the click just does not land.
//
// The classic dispatchers below are the 0.56 equivalents, and each one was
// exercised against this compositor with `hyprctl dispatch` during the
// session that wrote this — `focuswindow address:`, `closewindow address:`
// and `movetoworkspacesilent …,address:` all in anger, on real windows.
//
// If this fork is ever rebased onto a Hyprland that has the Lua API, the
// upstream form is the one to restore; it is better typed than string
// concatenation. It is simply not available here.
//
QtObject {
    id: root

    function luaString(value) {
        const text = String(value === undefined || value === null ? "" : value);
        return "\"" + text
            .replace(/\\/g, "\\\\")
            .replace(/"/g, "\\\"")
            .replace(/\n/g, "\\n")
            .replace(/\r/g, "\\r")
            .replace(/\t/g, "\\t") + "\"";
    }

    function normalizedAddress(value) {
        let rawAddress = "";
        if (value && typeof value === "object" && value.address !== undefined)
            rawAddress = String(value.address || "");
        else
            rawAddress = String(value === undefined || value === null ? "" : value);

        rawAddress = rawAddress.trim().toLowerCase();
        if (rawAddress.startsWith("address:"))
            rawAddress = rawAddress.slice(8);
        if (rawAddress === "" || rawAddress === "0x")
            return "";

        return rawAddress.startsWith("0x") ? rawAddress : "0x" + rawAddress;
    }

    function windowSelector(value) {
        const address = normalizedAddress(value);
        return address === "" ? "" : "address:" + address;
    }

    // NOT lua-quoted any more. A classic dispatcher takes the workspace as
    // a bare token — `workspace 3`, `workspace special:term1` — and a
    // quoted "special:term1" is not a workspace Hyprland can find.
    function workspaceExpression(value) {
        if (typeof value === "number" && isFinite(value))
            return String(Math.trunc(value));

        return String(value === undefined || value === null ? "" : value).trim();
    }

    function numberExpression(value) {
        const parsed = Number(value);
        return isFinite(parsed) ? String(Math.round(parsed)) : "0";
    }

    function dispatchExpression(expression) {
        const text = String(expression === undefined || expression === null ? "" : expression).trim();
        if (text === "")
            return false;

        Hyprland.dispatch(text);
        return true;
    }

    function focusWorkspace(workspace) {
        const target = workspaceExpression(workspace);
        if (target === "")
            return false;

        return dispatchExpression("workspace " + target);
    }

    // `follow` picks the dispatcher rather than being a parameter: the two
    // are separate dispatchers in the classic API, and the SILENT one is
    // the one that does not drag you to the destination.
    function moveWindowToWorkspace(address, workspace, follow) {
        const selector = windowSelector(address);
        const target = workspaceExpression(workspace);
        if (selector === "" || target === "")
            return false;

        const verb = follow ? "movetoworkspace" : "movetoworkspacesilent";
        return dispatchExpression(verb + " " + target + "," + selector);
    }

    // `exact` for absolute, bare numbers for relative — and a relative move
    // needs an explicit sign or Hyprland reads it as absolute, which is why
    // the positive case is prefixed rather than left to String().
    function moveWindowToPosition(address, x, y, relative) {
        const selector = windowSelector(address);
        if (selector === "")
            return false;

        const nx = numberExpression(x);
        const ny = numberExpression(y);
        if (relative) {
            const sx = nx.startsWith("-") ? nx : "+" + nx;
            const sy = ny.startsWith("-") ? ny : "+" + ny;
            return dispatchExpression("movewindowpixel " + sx + " " + sy + "," + selector);
        }

        return dispatchExpression("movewindowpixel exact " + nx + " " + ny + "," + selector);
    }

    function focusWindow(address) {
        const selector = windowSelector(address);
        if (selector === "")
            return false;

        return dispatchExpression("focuswindow " + selector);
    }

    function closeWindow(address) {
        const selector = windowSelector(address);
        if (selector === "")
            return false;

        return dispatchExpression("closewindow " + selector);
    }
}
