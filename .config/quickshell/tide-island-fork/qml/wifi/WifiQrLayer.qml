pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The port of qtile's popups/WifiQR.py, which was `s` inside
// the WiFi chord ($mod P then n, then s) and is the last item of the 14
// WifiPopup bindings that the island's own network list did not already
// answer.
//
// It shows a scannable QR for a saved network so a phone joins by pointing a
// camera at it, instead of by reading a 20-character PSK off a screen. All of
// the nmcli and qrencode work is in hypr/scripts/wifi-qr.py, including the
// three things about QR rendering that are deliberate and easy to "fix" into
// breakage — black on white regardless of theme, two qrencode passes so the
// scale is an integer, and byte mode pinned so a decoder cannot guess the
// charset. This file only shows what that script produced.
//
// THE ONE RULE THIS FILE OWNS: the symbol is drawn at its NATURAL pixel size,
// never stretched to fit. A QR resampled at a fractional ratio has soft
// module edges, and soft module edges are exactly what a phone camera fails
// to decode in poor light. The script is told how much room there is and
// picks an integer scale that fits inside it; whatever it returns is what
// gets painted, centred, with the leftover space left as white card.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    property string ssid: ""
    property string password: ""
    property string security: ""
    property string imagePath: ""
    property int imageSize: 0
    property string statusText: ""
    property bool failed: false

    // How much room the symbol has. Passed to the script so the integer
    // scale is chosen against the real box rather than against a guess.
    readonly property int qrBox: Metrics.px(300)
    readonly property real horizontalPadding: Metrics.pad(18)

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `root.showCondition ? 220 : 120` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    // Re-read every time it opens. The network can change while this is
    // closed, and a stale code is worse than no code: it fails on the phone
    // with no explanation of why.
    function reload() {
        root.ssid = "";
        root.password = "";
        root.imagePath = "";
        root.imageSize = 0;
        root.failed = false;
        root.statusText = "reading the connection…";
        qrProcess.command = [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-qr.py",
                             "--box", String(root.qrBox)];
        qrProcess.running = true;
    }

    onShowConditionChanged: {
        if (showCondition) {
            root.reload();
            forceActiveFocus();
        }
    }

    Process {
        id: qrProcess
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
                    return;
                }
                root.failed = false;
                root.password = String(parsed.password || "");
                root.imageSize = Number(parsed.size || 0);
                root.imagePath = String(parsed.path || "");
            }
        }
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_R:
            root.reload();
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(10)
        text: "Share Wi-Fi"
        color: "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(12)
        width: Math.min(implicitWidth, root.width * 0.5)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.ssid !== "" ? root.ssid : "—"
        color: root.failed ? "#ff6b6b" : "#9ad18a"
        font.pixelSize: Metrics.font(12)
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
    }

    // The white card. It is not decoration: the quiet zone is part of the QR
    // spec, and a dark desktop bleeding up to the modules costs a decoder the
    // margin it uses to find the symbol in the first place.
    Rectangle {
        id: card
        visible: root.imagePath !== "" && !root.failed
        anchors.horizontalCenter: parent.horizontalCenter
        y: Metrics.pad(38)
        width: root.imageSize + Metrics.pad(16)
        height: width
        radius: Metrics.px(10)
        color: "#ffffff"

        Image {
            anchors.centerIn: parent
            // Natural size, never scaled — see the file header.
            width: root.imageSize
            height: root.imageSize
            smooth: false
            // The path never changes (~/.cache/hypr/wifi-qr.png), so Qt's
            // image cache would happily show the PREVIOUS network's code
            // after a reconnect — right size, right white card, wrong
            // network, and nothing on screen to say so.
            cache: false
            source: root.imagePath !== "" ? "file://" + root.imagePath : ""
        }
    }

    // The failure case gets the same real estate rather than an empty box:
    // "not connected to Wi-Fi", "no stored password for this network" and
    // "enterprise networks can't be shared by QR" are three different
    // problems with three different answers.
    Text {
        visible: root.failed || root.imagePath === ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - root.horizontalPadding * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.statusText
        color: root.failed ? "#ff6b6b" : "#8a8a8a"
        font.pixelSize: Metrics.font(12)
        font.family: root.textFontFamily
    }

    Column {
        visible: card.visible
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(10)
        spacing: Metrics.px(2)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.password !== "" ? root.password : "(open network)"
            color: "#d0d0d0"
            font.pixelSize: Metrics.font(12)
            font.family: root.textFontFamily
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "scan with a phone  ·  q or Esc to close"
            color: "#6a6a6a"
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }
    }
}
