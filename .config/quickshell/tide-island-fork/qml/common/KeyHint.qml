pragma ComponentBehavior: Bound

import QtQuick

import "Metrics.js" as Metrics

//
// KeyHint — the key-hint footer, once.
//
// FORK — new file.
//
// WHAT IT REPLACES
// ----------------
// Nine panels each ended a file with the same anonymous Text:
//
//     Text {
//         anchors.bottom: parent.bottom
//         anchors.bottomMargin: Metrics.pad(8)     // or pad(10), or a raw 10
//         color: IslandTheme.textDisabled           // or textMuted
//         font.pixelSize: Metrics.font(10)          // or a raw 10
//         text: "j/k move · Enter join · d disconnect · r rescan · q close"
//     }
//
// Reserved under TWO property names — `hintHeight` on five panels,
// `footerHeight` on four — at FOUR different heights. Nobody chose that
// spread; it is one question answered nine separate times, which is the
// whole argument for this file existing.
//
// WHY THE STRING BECAME A LIST
// ----------------------------
// The old form is a single run-on string with the keys and the verbs in the
// same ink, separated by a middle dot that also appears INSIDE hints ("g/G
// first-last"). At font(10) muted, "j/k move · Enter join · d disconnect"
// is a texture rather than a legend — you cannot find a key in it without
// reading the whole line, which is the one thing a hint strip exists to
// spare you.
//
// So the key and its verb are separate now, and the key wears a chip:
// surfaceRaised at RADIUS.tight, the key in textSecondary, the verb in
// textMuted beside it. The chip is what makes the strip scannable, because
// it gives every key the same silhouette regardless of whether it is "j/k"
// or "Enter" — and it is the concentric child of the row it sits under
// (card 8 minus pad(4) is tight 4; see the RADIUS note in Metrics.js).
//
// It is a list rather than a formatted string on purpose. A string would put
// the separator, the case and the spacing back in the caller's hands, and
// getting nine callers to agree on those is precisely what did not happen
// last time.
//
// OVERFLOW IS ELIDED AT THE PAIR, NOT AT THE CHARACTER
// ----------------------------------------------------
// The old Text had `elide: ElideRight`, which on a narrow panel produces
// "… r resca…" — a chip for a key you cannot read. Pairs that do not fit
// are dropped whole instead, so what remains is always legible. Callers
// therefore put the hints they care about FIRST; `q close` last is not
// alphabetical, it is the one everybody already knows.
//
Item {
    id: root

    // [{ key: "j/k", label: "move" }, …]. Order is priority order — see the
    // overflow note above.
    property var hints: []

    // Passed down from the island the same way every panel takes it, rather
    // than reached for through a singleton: the font families are user config
    // and the panels already thread them.
    property string textFontFamily: ""

    // The strip's own height. Callers that compute a `preferredHeight` should
    // use Metrics.chromeFooter() directly rather than reading this back, so
    // the arithmetic does not depend on this item existing yet.
    implicitHeight: Metrics.chromeFooter()

    readonly property real chipHeight: Metrics.px(15)
    readonly property real pairSpacing: Metrics.pad(12)

    // ---- WHY THE FIT IS COMPUTED AND NOT LEFT TO THE LAYOUT ----
    //
    // A Row clips its overflowing children rather than dropping them, and a
    // clipped chip is a chip with half a key in it. So the pairs that fit are
    // decided here, in one pass over the widths the Repeater has already
    // measured, and the Row is only ever given children it can hold.
    //
    // Recomputed on width and on hints, which is every input it has. It is
    // O(n) over at most a handful of pairs and runs when a panel opens or
    // resizes, not per frame.
    property var visibleHints: []

    function recomputeFit() {
        const source = root.hints || [];
        if (root.width <= 0 || source.length === 0) {
            root.visibleHints = source;
            return;
        }
        let used = 0;
        const kept = [];
        for (let i = 0; i < source.length; i++) {
            const w = measure.widthOf(source[i]);
            const next = used + (kept.length > 0 ? root.pairSpacing : 0) + w;
            if (next > root.width && kept.length > 0)
                break;
            used = next;
            kept.push(source[i]);
        }
        root.visibleHints = kept;
    }

    onWidthChanged: root.recomputeFit()
    onHintsChanged: root.recomputeFit()
    Component.onCompleted: root.recomputeFit()

    // Off-screen measurement. Two hidden Texts rather than a hidden copy of
    // the whole delegate: width is all that is asked for, and a real delegate
    // would also build a Rectangle per pair per measurement.
    //
    // These shape LATIN ONLY — the hint vocabulary is keycaps and English
    // verbs, both supplied by the caller as literals in this tree. That is
    // deliberate and is the `"Ag国"` lesson: a hidden Text is still a shaped
    // Text, and shaping a script maps its face for the life of the process.
    Item {
        id: measure
        visible: false
        width: 0
        height: 0

        function widthOf(hint) {
            keyProbe.text = String(hint && hint.key ? hint.key : "");
            labelProbe.text = String(hint && hint.label ? hint.label : "");
            const chip = keyProbe.implicitWidth + Metrics.pad(10);
            return chip + Metrics.pad(6) + labelProbe.implicitWidth;
        }

        Text {
            id: keyProbe
            font.family: root.textFontFamily
            font.pixelSize: Metrics.TYPE.caption
            font.weight: Font.DemiBold
        }

        Text {
            id: labelProbe
            font.family: root.textFontFamily
            font.pixelSize: Metrics.TYPE.caption
        }
    }

    Row {
        id: strip
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pairSpacing

        Repeater {
            model: root.visibleHints

            delegate: Row {
                id: pair

                required property var modelData

                spacing: Metrics.pad(6)

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: keyText.implicitWidth + Metrics.pad(10)
                    height: root.chipHeight
                    radius: Metrics.RADIUS.tight
                    color: IslandTheme.surfaceRaised
                    border.width: 1
                    border.color: IslandTheme.hairline

                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: String(pair.modelData && pair.modelData.key ? pair.modelData.key : "")
                        color: IslandTheme.textSecondary
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.TYPE.caption
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(pair.modelData && pair.modelData.label ? pair.modelData.label : "")
                    color: IslandTheme.textMuted
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.TYPE.caption
                }
            }
        }
    }
}
