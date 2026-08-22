import QtQuick
import Quickshell
import Quickshell.Wayland

//
// FORK — new file (second attempt). "i want dropdown card as this pill
// bro" — the first attempt at this was a real dropdown, then got folded
// into the workspace pill's own text on request ("be the workspace part
// itself"), then asked back OUT into a real dropdown again once that read
// as too little (one line of text, not an actual list). This is that
// dropdown: hangs directly under the workspace pill (anchorX/anchorTop,
// fed from redesign-e-final.qml, which is the only file that actually
// knows where centerStrip sits), while the pill itself stays completely
// untouched — workspace icons, app stack, all of it, exactly as it always
// renders.
//
// SAME READ-ONLY CONSTRAINT AS THE TAKEOVER FACES
// -------------------------------------------------
// No NotificationServer of its own — see notifyFace's own comment in
// redesign-e-final.qml for why (the island already owns
// org.freedesktop.Notifications while it's running, and that's a
// one-owner job). This list is built from demo.notifyHistory —
// everything the passive `busctl monitor | jq` watcher has seen cross
// the bus since THIS bar started, not a real persisted history the way a
// NotificationServer would carry. `dd` only removes an entry from this
// local list; there's no notification object here to actually call
// Close on.
//
// VIM MOTION, THE ACTUAL SUBSET
// ------------------------------
// j/k move the selection, gg/G jump to the top/bottom (gg needs the
// double-tap window below since there is no true modal grammar here,
// just single keypresses), dd removes the selected entry, Escape or q
// closes.
PanelWindow {
    id: center

    signal requestClose()

    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "topbar-notification-center"
    // OnDemand, not Exclusive — the exact reason redesign-e-final.qml's
    // own `bar` no longer takes ANY keyboard focus records: Exclusive
    // blocks Hyprland's global dispatch (workspace switching included)
    // while held, not just keyboard-focused input. Verified live before
    // settling on this: a real `hyprctl dispatch workspace N` was refused
    // while an Exclusive surface was up, and succeeded once this was
    // OnDemand instead.
    WlrLayershell.keyboardFocus: center.visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Dropdown anchor point, fed from redesign-e-final.qml: `anchorX` is
    // centerStrip's own screen-space centre, `anchorTop` is the
    // screen-space Y just under `bar` itself.
    property real anchorX: 0
    property real anchorTop: 0
    anchors { top: true; left: true }
    margins.top: center.anchorTop
    margins.left: Math.round(center.anchorX - center.popupWidth / 2)

    readonly property int popupWidth: Math.min(Metrics.s(360),
        (center.screen ? center.screen.width : 1366) - Metrics.s(40))
    readonly property int popupHeight: Math.min(Metrics.s(320),
        (center.screen ? center.screen.height : 768) - Metrics.s(48))
    implicitWidth: center.popupWidth
    implicitHeight: center.rows.length === 0 ? Metrics.s(56)
        : Math.min(center.popupHeight, head.height + footer.height
                   + Metrics.s(16) + Math.min(center.rows.length, 5) * rowHeightGuess)
    readonly property int rowHeightGuess: Metrics.textSize * 2 + Metrics.s(18)

    property int selected: 0
    // newest last in demo.notifyHistory; shown newest FIRST.
    readonly property var rows: {
        const out = [];
        const src = demo.notifyHistory;
        for (let i = src.length - 1; i >= 0; i--) out.push(src[i]);
        return out;
    }

    onVisibleChanged: {
        if (center.visible)
            center.selected = 0;
        else
            center.requestClose();
    }

    // ---- gg/dd double-tap state ----
    property string pendingKey: ""
    Timer { id: pendingReset; interval: 400; onTriggered: center.pendingKey = "" }

    function clampSelected() {
        if (center.selected < 0) center.selected = 0;
        if (center.selected > center.rows.length - 1) center.selected = Math.max(0, center.rows.length - 1);
    }

    function deleteSelected() {
        if (center.rows.length === 0) return;
        const realIndex = demo.notifyHistory.length - 1 - center.selected;
        const hist = demo.notifyHistory.slice();
        hist.splice(realIndex, 1);
        demo.notifyHistory = hist;
        center.clampSelected();
    }

    function scrollToSelected() {
        const rowH = center.rowHeightGuess;
        const top = center.selected * rowH;
        const bottom = top + rowH;
        if (top < listView.contentY)
            listView.contentY = top;
        else if (bottom > listView.contentY + listView.height)
            listView.contentY = bottom - listView.height;
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Metrics.s(10)
        // Same plate/border language every Strip on this bar uses, not a
        // separate look — "same style like the new bar" carries over
        // from the bottom-bar ask.
        color: BarTheme.alpha(BarTheme.plate, 0.94)
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.accent, 0.35)

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Item {
            id: head
            x: card.width * 0.06
            y: Metrics.s(10)
            width: card.width * 0.88
            height: Metrics.s(20)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: BarTheme.fg
                font.family: Metrics.textFamily
                font.bold: true
                font.pixelSize: Metrics.textSize + 2
                renderType: Text.NativeRendering
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: center.rows.length === 0 ? "" : (center.selected + 1) + "/" + center.rows.length
                color: BarTheme.alpha(BarTheme.fg, 0.6)
                font.family: Metrics.textFamily
                font.pixelSize: Metrics.textSize - 1
                renderType: Text.NativeRendering
            }
        }

        Text {
            visible: center.rows.length === 0
            anchors.centerIn: parent
            text: "No notifications seen this session"
            color: BarTheme.alpha(BarTheme.fg, 0.5)
            font.family: Metrics.textFamily
            font.pixelSize: Metrics.textSize
            renderType: Text.NativeRendering
        }

        Flickable {
            id: listView
            visible: center.rows.length > 0
            x: card.width * 0.06
            y: Metrics.s(34)
            width: card.width * 0.88
            height: footer.y - y - Metrics.s(6)
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            onHeightChanged: center.scrollToSelected()
            Connections {
                target: center
                function onSelectedChanged() { center.scrollToSelected(); }
            }

            Column {
                id: col
                width: parent.width
                spacing: Metrics.s(4)

                Repeater {
                    model: center.rows
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: col.width
                        height: rowCol.implicitHeight + Metrics.s(8)
                        radius: Metrics.s(6)
                        color: index === center.selected
                            ? BarTheme.alpha(BarTheme.accent, 0.18) : "transparent"
                        border.width: index === center.selected ? 1 : 0
                        border.color: BarTheme.alpha(BarTheme.accent, 0.5)

                        Column {
                            id: rowCol
                            x: Metrics.s(8)
                            y: Metrics.s(4)
                            width: parent.width - Metrics.s(16)
                            spacing: Metrics.s(1)
                            Row {
                                width: parent.width
                                Text {
                                    width: parent.width - timeLabel.implicitWidth
                                    text: row.modelData.app + "  " + row.modelData.summary
                                    color: BarTheme.fg
                                    font.family: Metrics.textFamily
                                    font.bold: true
                                    font.pixelSize: Metrics.textSize - 1
                                    elide: Text.ElideRight
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    id: timeLabel
                                    text: row.modelData.time
                                    color: BarTheme.alpha(BarTheme.fg, 0.5)
                                    font.family: Metrics.textFamily
                                    font.pixelSize: Metrics.textSize - 2
                                    renderType: Text.NativeRendering
                                }
                            }
                            Text {
                                visible: row.modelData.body !== ""
                                width: parent.width
                                text: row.modelData.body
                                color: BarTheme.alpha(BarTheme.fg, 0.6)
                                font.family: Metrics.textFamily
                                font.pixelSize: Metrics.textSize - 2
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                renderType: Text.NativeRendering
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: center.selected = row.index
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            x: card.width * 0.06
            y: card.height - Metrics.s(10) - Metrics.s(16)
            width: card.width * 0.88
            height: Metrics.s(16)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "j/k move · gg/G top/bottom · dd remove · Esc close"
                color: BarTheme.alpha(BarTheme.fg, 0.45)
                font.family: Metrics.textFamily
                font.pixelSize: Metrics.textSize - 3
                renderType: Text.NativeRendering
            }
        }
    }

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            const key = event.key;
            const text = event.text;

            if (key === Qt.Key_Escape || text === "q") {
                center.visible = false;
                event.accepted = true;
                return;
            }
            if (text === "j" || key === Qt.Key_Down) {
                center.selected += 1;
                center.clampSelected();
                event.accepted = true;
                return;
            }
            if (text === "k" || key === Qt.Key_Up) {
                center.selected -= 1;
                center.clampSelected();
                event.accepted = true;
                return;
            }
            if (key === Qt.Key_G && (event.modifiers & Qt.ShiftModifier)) {
                center.selected = Math.max(0, center.rows.length - 1);
                event.accepted = true;
                return;
            }
            if (text === "g") {
                if (center.pendingKey === "g") {
                    center.selected = 0;
                    center.pendingKey = "";
                    pendingReset.stop();
                } else {
                    center.pendingKey = "g";
                    pendingReset.restart();
                }
                event.accepted = true;
                return;
            }
            if (text === "d") {
                if (center.pendingKey === "d") {
                    center.deleteSelected();
                    center.pendingKey = "";
                    pendingReset.stop();
                } else {
                    center.pendingKey = "d";
                    pendingReset.restart();
                }
                event.accepted = true;
                return;
            }
        }
    }
}
