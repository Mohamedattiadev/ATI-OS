import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/WifiQR.py, in Quickshell, for the topbar.
//
// WHAT WAS ACTUALLY BROKEN
// ------------------------
// The chip was not unbound and the script was not failing. Measured:
//
//     $ python3 ~/.config/hypr/scripts/wifi-qr.py
//     {"ok": true, "ssid": "…", "password": "…", "security": "wpa-psk",
//      "path": "/home/ati/.cache/hypr/wifi-qr.png", "size": 222,
//      "status": "scan with a phone"}          exit 0
//
// It is a DATA PRODUCER. It writes a PNG and prints where it put it, and the
// island renders that in its `wifi_qr` state. bar-action's native branch ran
// it and threw stdout away, so the whole feature was one missing viewer —
// the QR was being generated correctly on every press, into a file nobody
// opened.
//
// So this file is a viewer and nothing else. Every hard part of QR rendering
// stays in the script, where its three deliberate decisions are already
// written down: black on white whatever the theme is, two qrencode passes so
// the scale is an integer, and byte mode pinned so a decoder cannot guess the
// charset.
//
// THE RULE THIS FILE OWNS, INHERITED FROM WifiQrLayer.qml
// -------------------------------------------------------
// The symbol is painted at its NATURAL pixel size, never stretched to fit.
// A QR resampled at a fractional ratio has soft module edges, and soft
// module edges are what a phone camera fails to decode in poor light. The
// script is told the box and picks an integer scale inside it; whatever it
// returns is painted, centred, with the leftover left as white card.
//
// POPUP_W=380, POPUP_H=500 are WifiQR.py's. This is 420x560, and the
// difference is exactly the chrome that file does not have: PopupChrome's
// header and keycap bar are 138 px before the body starts, against that
// file's 90. Keeping 500 would have paid for the shared frame out of the
// QR's own box — a smaller symbol on the same screen, which is the one
// dimension here that has a functional cost rather than a visual one.
PopupChrome {
    id: root

    // NOT `closed` — QQuickWindow already has one, and the override is
    // dropped with a warning rather than an error. NetworkPopup's header
    // has the full note.
    signal requestClose()

    popupWidth: PopupMetrics.s(420)
    popupHeight: PopupMetrics.s(560)

    titleIcon: String.fromCodePoint(0xF0928)
    title: "Share Wi-Fi"
    subtitle: root.security === "" ? "reading the connection…"
        : (root.security === "open" ? "open network" : root.security)

    badgeLabel: "network"
    // Elided HERE and not in PopupChrome. The badge is right-aligned in the
    // same header row as the title and nothing clips it, so an over-long
    // value runs left THROUGH the title rather than being cut — and the cap
    // depends on the popup's width, which is the caller's. Measured on this
    // one: at 420 px the title ends and the badge begins with about a
    // character to spare at 18, which is what this network's name happens to
    // be. The full SSID is still in the QR and in the footer's own text.
    badgeValue: root.ssid === "" ? "—"
        : (root.ssid.length > 18 ? root.ssid.substring(0, 17) + "…" : root.ssid)

    // Two keys, so the wallpaper picker's five-space gap is right here —
    // this is the bar that bar was measured for, not the ten-chip one the
    // network popup had to squeeze.
    hints: [
        { key: "r",   desc: "refresh" },
        { key: "Esc", desc: "close" }
    ]

    // ---- STATE ----
    property string ssid: ""
    property string password: ""
    property string security: ""
    property string imagePath: ""
    property int imageSize: 0
    property string statusText: "reading the connection…"
    property bool failed: false

    // How much room the symbol has, passed to the script so its integer
    // scale is chosen against the real box rather than against a guess.
    // Derived from the body, not typed twice: the card is imageSize+16 and
    // the password block below it needs its own row.
    readonly property int qrBox: PopupMetrics.s(240)

    // ---- THE READ ----
    //
    // Every open, not once. The network can change while this is closed and
    // a stale code is worse than no code — it fails on the phone with
    // nothing on screen to say why.
    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    root.failed = true;
                    root.statusText = "wifi-qr produced no readable output";
                    return;
                }
                root.ssid = String(parsed.ssid || "");
                root.security = String(parsed.security || "");
                root.statusText = String(parsed.status || "");
                if (!parsed.ok) {
                    root.failed = true;
                    root.imagePath = "";
                    root.imageSize = 0;
                    return;
                }
                root.failed = false;
                root.password = String(parsed.password || "");
                root.imageSize = Number(parsed.size || 0);
                root.imagePath = String(parsed.path || "");
            }
        }
    }

    function reload() {
        root.ssid = "";
        root.password = "";
        root.security = "";
        root.imagePath = "";
        root.imageSize = 0;
        root.failed = false;
        root.statusText = "reading the connection…";
        // Absolute. Quickshell is started by the compositor, so its PATH is
        // the session's — popups.qml's theme-apply line carries the same note.
        qrProc.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-qr.py",
                          "--box", String(root.qrBox)];
        qrProc.running = true;
    }

    Component.onCompleted: root.reload()

    onKeyPressed: (key, mods, text) => {
        if (key === Qt.Key_R)
            root.reload();
    }

    onDismissed: root.requestClose()

    // ---- BODY ----
    Item {
        anchors.fill: parent

        // THE WHITE CARD IS NOT DECORATION, AND IT IS NOT THEMED.
        //
        // One of the four deliberate exceptions to the token layer, listed in
        // IslandTheme.qml. The quiet zone is part of the QR spec and "light
        // field" means white, not gruvbox #282828 — a themed card is a QR
        // that phones refuse. The one place where following the palette would
        // stop the feature working rather than merely look wrong.
        Rectangle {
            id: card
            visible: root.imagePath !== "" && !root.failed
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: root.imageSize + PopupMetrics.s(16)
            height: width
            radius: PopupMetrics.s(10)
            color: "#ffffff"

            Image {
                anchors.centerIn: parent
                // Natural size, never scaled — see the file header.
                width: root.imageSize
                height: root.imageSize
                smooth: false
                // The path never changes (~/.cache/hypr/wifi-qr.png), so Qt's
                // image cache would happily show the PREVIOUS network's code
                // after a reconnect: right size, right white card, wrong
                // network, and nothing on screen to say so.
                cache: false
                source: root.imagePath !== "" ? "file://" + root.imagePath : ""
            }
        }

        // The password, on its own card, the way WifiQR.py draws it at
        // fy(392): the QR is for the phone and this line is for the laptop
        // in the room that cannot point a camera at the screen.
        Rectangle {
            visible: card.visible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: card.bottom
            anchors.topMargin: PopupMetrics.s(10)
            width: card.width
            height: PopupMetrics.s(48)
            radius: PopupMetrics.s(10)
            color: root.cSurface

            Column {
                anchors.centerIn: parent
                spacing: PopupMetrics.s(2)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "password"
                    color: root.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.rowSize * 0.833)
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.password !== "" ? root.password : "(open network)"
                    color: root.cFg
                    font.family: PopupMetrics.font
                    font.pixelSize: PopupMetrics.rowSize
                    renderType: Text.NativeRendering
                }
            }
        }

        // The failure case gets the same real estate rather than an empty
        // box. "not connected to Wi-Fi", "no stored password for this
        // network" and "enterprise networks can't be shared by QR" are three
        // different problems with three different answers, and the script
        // already distinguishes them.
        Text {
            visible: !card.visible
            anchors.centerIn: parent
            width: parent.width - PopupMetrics.s(24)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.statusText
            color: root.failed ? IslandTheme.danger : root.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.rowSize
            renderType: Text.NativeRendering
        }
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: root.failed ? root.statusText
            : (card.visible ? "scan with a phone  ·  Esc to close"
                            : root.statusText)
        color: root.failed ? IslandTheme.danger : root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
