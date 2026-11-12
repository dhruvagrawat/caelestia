pragma ComponentBehavior: Bound

// Lights tab for the caelestia dashboard (fork only).
// Keyboard + two Bluetooth LED strips, driven by hypr/scripts/lightd.py.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    readonly property string daemon: Quickshell.env("HOME") + "/.config/hypr/scripts/lightd.py"
    readonly property var order: ["kb", "s1", "s2"]
    property var lights: ({})
    property real timerEnd: 0
    property var selected: ["kb", "s1", "s2"]
    property real now: Date.now()

    readonly property var lead: lights[selected[0]] ?? null
    readonly property bool anyAnimated: order.some(k => lights[k]?.on && lights[k]?.mode !== "static")

    readonly property var presets: [
        { name: "Theme", hex: "theme" },
        { name: "Neon pink", hex: "ff2a6d" },
        { name: "Cyber cyan", hex: "05d9e8" },
        { name: "Volt", hex: "f9f002" },
        { name: "Ultraviolet", hex: "9d00ff" },
        { name: "Red", hex: "ff0033" },
        { name: "Sunset", hex: "ff6a00" },
        { name: "Matrix", hex: "39ff14" },
        { name: "Deep blue", hex: "0040ff" },
        { name: "White", hex: "ffffff" }
    ]
    readonly property var modes: [
        { id: "static", label: "Static" },
        { id: "breathe", label: "Breathe" },
        { id: "rainbow", label: "Rainbow" },
        { id: "strobe", label: "Strobe" },
        { id: "ambient", label: "Screen sync" }
    ]
    readonly property var monitors: [
        { id: "DP-1", label: "DP-1 (left)" },
        { id: "HDMI-A-1", label: "HDMI (right)" },
        { id: "eDP-1", label: "Laptop" }
    ]

    function toHex(c: color): string {
        return [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
    }

    function send(msg: var): void {
        Quickshell.execDetached(["/usr/bin/python3", "-I", daemon, "send", JSON.stringify(msg)]);
    }

    function act(cmd: string, extra: var): void {
        if (selected.length === 0)
            return;
        send(Object.assign({ cmd: cmd, targets: selected }, extra));
    }

    function toggleSelect(key: string): void {
        const s = selected.slice();
        const i = s.indexOf(key);
        if (i >= 0)
            s.splice(i, 1);
        else
            s.push(key);
        selected = order.filter(k => s.includes(k));
    }

    // Mirror of lightd's software effects, for the live preview
    function previewColour(l: var, t: real): color {
        if (!l || !l.on)
            return Qt.rgba(0.08, 0.08, 0.1, 1);
        const sp = ({ slow: 0.35, med: 1.0, fast: 2.5 })[l.speed] ?? 1;
        let k = l.brightness / 100;
        let c = Qt.color("#" + (l.mode === "ambient" && l.live ? l.live : l.hex));
        if (l.mode === "breathe")
            k *= 0.12 + 0.88 * (0.5 + 0.5 * Math.sin(t * sp * 2.2));
        else if (l.mode === "strobe")
            k *= ((t * sp * 4) % 1) < 0.5 ? 1 : 0.05;
        else if (l.mode === "rainbow")
            c = Qt.hsva((t * sp * 0.08) % 1, 1, 1, 1);
        return Qt.rgba(c.r * k, c.g * k, c.b * k, 1);
    }

    implicitWidth: 840
    implicitHeight: layout.implicitHeight

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/lights/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.lights = d.lights ?? {};
                root.timerEnd = d.timerEnd ?? 0;
            } catch (e) {}
        }
    }

    Timer {
        running: root.visible && (root.anyAnimated || root.timerEnd > 0)
        repeat: true
        interval: root.anyAnimated ? 50 : 1000
        onTriggered: root.now = Date.now()
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.large

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "light_group"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.large
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: qsTr("Room lights")
                    font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
                }

                StyledText {
                    text: {
                        const n = root.selected.length;
                        const names = root.selected.map(k => root.lights[k]?.name ?? k).join(" + ");
                        const sync = n > 1 ? qsTr("Synced: %1").arg(names) : n === 1 ? qsTr("Controlling: %1").arg(names) : qsTr("Select lights to control");
                        if (root.timerEnd > 0) {
                            const mins = Math.max(0, Math.ceil((root.timerEnd - root.now) / 60000));
                            return sync + " · " + qsTr("off in %1 min").arg(mins);
                        }
                        return sync;
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            Choice {
                Layout.fillWidth: false
                text: qsTr("Release strips")
                onClicked: root.send({ cmd: "release" })
            }

            Choice {
                Layout.fillWidth: false
                text: qsTr("Reconnect")
                onClicked: root.send({ cmd: "reconnect" })
            }
        }

        // Live preview + selection
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            Repeater {
                model: root.order

                StyledRect {
                    id: device

                    required property string modelData
                    readonly property var light: root.lights[modelData] ?? null
                    readonly property bool isSelected: root.selected.includes(modelData)
                    readonly property color glow: root.previewColour(light, root.now / 1000)

                    Layout.fillWidth: true
                    Layout.preferredWidth: modelData === "kb" ? 3 : 2
                    implicitHeight: 150
                    radius: Tokens.rounding.large
                    color: Colours.tPalette.m3surfaceContainer
                    border.width: isSelected ? 2 : 1
                    border.color: isSelected ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.12)

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleSelect(device.modelData)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.small

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                Layout.fillWidth: true
                                text: device.light?.name ?? device.modelData
                                font: Tokens.font.body.medium
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: device.light?.connected ? "#39ff14" : "#ff3355"
                            }

                            MaterialIcon {
                                text: device.isSelected ? "check_box" : "check_box_outline_blank"
                                color: device.isSelected ? Colours.palette.m3primary : Colours.palette.m3outline
                            }
                        }

                        // Simulated light
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Glow
                            Rectangle {
                                anchors.centerIn: visual
                                width: visual.width + 18
                                height: visual.height + 18
                                radius: 10
                                color: device.glow
                                opacity: device.light?.on ? 0.35 : 0
                            }

                            Item {
                                id: visual

                                anchors.centerIn: parent
                                width: parent.width - 24
                                height: device.modelData === "kb" ? parent.height - 16 : 14

                                // LED strip
                                Rectangle {
                                    visible: device.modelData !== "kb"
                                    anchors.fill: parent
                                    radius: 3
                                    color: device.glow
                                    border.width: 1
                                    border.color: Qt.lighter(device.glow, 1.6)
                                }

                                // Keyboard
                                Column {
                                    visible: device.modelData === "kb"
                                    anchors.fill: parent
                                    spacing: 3

                                    Repeater {
                                        model: 4

                                        Row {
                                            required property int index

                                            spacing: 3

                                            Repeater {
                                                model: 14

                                                Rectangle {
                                                    width: (visual.width - 13 * 3) / 14
                                                    height: (visual.height - 3 * 3) / 4
                                                    radius: 2
                                                    color: Qt.rgba(0.1, 0.1, 0.13, 1)
                                                    border.width: 1
                                                    border.color: device.glow
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const l = device.light;
                                if (!l)
                                    return qsTr("Starting…");
                                if (!l.on)
                                    return qsTr("Off");
                                const m = root.modes.find(x => x.id === l.mode)?.label ?? l.mode;
                                return `${m} · ${l.brightness}%` + (l.connected ? "" : " · " + qsTr("not connected"));
                            }
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Individual selection
        ButtonRow {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            Repeater {
                model: [
                    { key: "kb", label: qsTr("Keyboard") },
                    { key: "s1", label: qsTr("LED strip 1") },
                    { key: "s2", label: qsTr("LED strip 2") }
                ]

                Choice {
                    required property var modelData

                    text: (root.selected.includes(modelData.key) ? "✓ " : "") + modelData.label
                    checked: root.selected.includes(modelData.key)
                    internalChecked: checked
                    onClicked: root.toggleSelect(modelData.key)
                }
            }
        }

        // Sync groups
        ButtonRow {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            Repeater {
                model: [
                    { label: qsTr("All 3"), keys: ["kb", "s1", "s2"] },
                    { label: qsTr("Both strips"), keys: ["s1", "s2"] },
                    { label: qsTr("Keyboard + strip 1"), keys: ["kb", "s1"] },
                    { label: qsTr("Keyboard + strip 2"), keys: ["kb", "s2"] }
                ]

                Choice {
                    required property var modelData

                    text: modelData.label
                    checked: JSON.stringify(root.selected) === JSON.stringify(modelData.keys)
                    internalChecked: checked
                    onClicked: root.selected = modelData.keys
                }
            }
        }

        // Power + modes + speed
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.large

            ButtonRow {
                spacing: Tokens.spacing.small

                Choice {
                    text: qsTr("On")
                    checked: root.lead?.on ?? false
                    internalChecked: checked
                    onClicked: root.act("power", { on: true })
                }

                Choice {
                    text: qsTr("Off")
                    checked: !(root.lead?.on ?? true)
                    internalChecked: checked
                    onClicked: root.act("power", { on: false })
                }
            }

            ButtonRow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.modes

                    Choice {
                        required property var modelData

                        text: modelData.label
                        checked: root.lead?.mode === modelData.id
                        internalChecked: checked
                        onClicked: root.act("mode", { mode: modelData.id })
                    }
                }
            }

            ButtonRow {
                spacing: Tokens.spacing.small

                Repeater {
                    model: ["slow", "med", "fast"]

                    Choice {
                        required property string modelData

                        text: modelData === "med" ? qsTr("Med") : modelData === "slow" ? qsTr("Slow") : qsTr("Fast")
                        checked: root.lead?.speed === modelData
                        internalChecked: checked
                        onClicked: root.act("speed", { speed: modelData })
                    }
                }
            }
        }

        // Screen sync: which monitor to follow
        RowLayout {
            visible: root.lead?.mode === "ambient"
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "monitor"
                color: Colours.palette.m3primary
            }

            StyledText {
                text: qsTr("Follow colours of")
                color: Colours.palette.m3onSurfaceVariant
            }

            ButtonRow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: root.monitors

                    Choice {
                        required property var modelData

                        text: modelData.label
                        checked: root.lead?.monitor === modelData.id
                        internalChecked: checked
                        onClicked: root.act("monitor", { monitor: modelData.id })
                    }
                }
            }
        }

        // Colour presets
        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            columns: 10
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            Repeater {
                model: root.presets

                TextButton {
                    required property var modelData
                    readonly property string hex: modelData.hex === "theme" ? root.toHex(Colours.palette.m3primary) : modelData.hex
                    readonly property bool selectedColour: (root.lead?.hex ?? "") === hex.toLowerCase()

                    Layout.fillWidth: true
                    isToggle: false
                    verticalPadding: Tokens.padding.medium
                    font: Tokens.font.body.builders.small.size(Math.round(Tokens.font.body.small.pointSize * 0.85)).build()
                    text: selectedColour ? "● " + modelData.name : modelData.name
                    inactiveColour: "#" + hex
                    activeColour: "#" + hex
                    inactiveOnColour: Qt.color("#" + hex).hslLightness > 0.55 ? "#101010" : "#ffffff"
                    activeOnColour: inactiveOnColour
                    onClicked: root.act("colour", { hex: hex })
                }
            }
        }

        // Brightness
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "brightness_6"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledSlider {
                id: bright

                Layout.fillWidth: true
                implicitHeight: Tokens.padding.large * 2
                from: 1
                to: 100
                value: root.lead?.brightness ?? 100
                onPressedChanged: if (!pressed) root.act("brightness", { value: Math.round(value) })
            }

            StyledText {
                Layout.preferredWidth: 44
                text: `${Math.round(bright.value)}%`
                horizontalAlignment: Text.AlignRight
            }
        }

        // Timer
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.bottomMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "timer"
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                text: qsTr("Turn all lights off in")
                color: Colours.palette.m3onSurfaceVariant
            }

            ButtonRow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: [15, 30, 60, 120]

                    Choice {
                        required property int modelData

                        text: modelData < 60 ? `${modelData} min` : `${modelData / 60} h`
                        onClicked: root.send({ cmd: "timer", minutes: modelData })
                    }
                }

                Choice {
                    text: qsTr("Cancel")
                    disabled: root.timerEnd <= 0
                    onClicked: root.send({ cmd: "timer", minutes: 0 })
                }
            }
        }
    }

    component Choice: TextButton {
        fillWidth: true
        type: TextButton.Tonal
        isToggle: false
        horizontalPadding: Tokens.padding.small
        verticalPadding: Tokens.padding.small
    }
}
