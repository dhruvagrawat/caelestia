pragma ComponentBehavior: Bound

// ASUS card for the caelestia utilities popup (fork only).
// Keyboard backlight brightness / effect / colour and battery charge limit via asusctl.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property int kbBrightness: -1
    property int chargeLimit: -1
    property int ledMode: -1
    property string colour: "ffffff"

    readonly property var brightnessLevels: [
        { value: 0, label: "Off", arg: "off" },
        { value: 1, label: "Low", arg: "low" },
        { value: 2, label: "Med", arg: "med" },
        { value: 3, label: "High", arg: "high" }
    ]
    readonly property var effects: [
        { value: 0, label: "Static", arg: "static" },
        { value: 1, label: "Breathe", arg: "breathe" },
        { value: 2, label: "Rainbow", arg: "rainbow-cycle" },
        { value: 10, label: "Pulse", arg: "pulse" }
    ]
    readonly property var limits: [60, 80, 90, 100]
    readonly property var swatches: [toHex(Colours.palette.m3primary), "ffffff", "ff0000", "ff6a00", "ffd000", "00ff66", "00aaff", "8a2be2", "ff00aa"]

    function toHex(c: color): string {
        return [c.r, c.g, c.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
    }

    function exec(args: list<string>): void {
        Quickshell.execDetached(args);
        refreshDelay.restart();
    }

    function setBrightness(level: var): void {
        kbBrightness = level.value;
        exec(["asusctl", "leds", "set", level.arg]);
    }

    function setEffect(arg: string, hex: string): void {
        const base = ["asusctl", "aura", "effect", arg];
        if (arg === "static" || arg === "pulse")
            exec(base.concat(["-c", hex]));
        else if (arg === "breathe")
            exec(base.concat(["--colour", hex, "--colour2", "000000", "--speed", "med"]));
        else
            exec(base.concat(["--speed", "med"]));
    }

    function setColour(hex: string): void {
        colour = hex;
        const current = effects.find(e => e.value === ledMode);
        // Rainbow has no colour, so picking a colour switches to static
        setEffect(current && current.arg !== "rainbow-cycle" ? current.arg : "static", hex);
    }

    function setLimit(limit: int): void {
        chargeLimit = limit;
        exec(["asusctl", "battery", "limit", String(limit)]);
    }

    implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    Component.onCompleted: reader.running = true

    Timer {
        id: refreshDelay

        interval: 600
        onTriggered: reader.running = true
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.visible
        onTriggered: reader.running = true
    }

    Process {
        id: reader

        command: ["sh", "-c", "cat /sys/class/leds/asus::kbd_backlight/brightness; cat /sys/class/power_supply/BAT0/charge_control_end_threshold; busctl --system get-property xyz.ljones.Asusd /xyz/ljones/aura/tuf xyz.ljones.Aura LedModeData"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                root.kbBrightness = parseInt(lines[0]);
                root.chargeLimit = parseInt(lines[1]);
                // "(uu(yyy)(yyy)ss) MODE ZONE R G B R2 G2 B2 ..."
                const parts = (lines[2] ?? "").split(" ");
                if (parts.length > 5) {
                    root.ledMode = parseInt(parts[1]);
                    root.colour = [parts[3], parts[4], parts[5]].map(v => parseInt(v).toString(16).padStart(2, "0")).join("");
                }
            }
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: kbIcon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: root.kbBrightness > 0 ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: kbIcon

                    anchors.centerIn: parent
                    text: "keyboard"
                    color: root.kbBrightness > 0 ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Keyboard lighting")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const e = root.effects.find(x => x.value === root.ledMode);
                        const b = root.brightnessLevels.find(x => x.value === root.kbBrightness);
                        return `${b ? b.label : "?"} · ${e ? e.label : "?"}`;
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.brightnessLevels

                Choice {
                    required property var modelData

                    text: modelData.label
                    checked: root.kbBrightness === modelData.value
                    onClicked: root.setBrightness(modelData)
                }
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.effects

                Choice {
                    required property var modelData

                    text: modelData.label
                    checked: root.ledMode === modelData.value
                    onClicked: {
                        root.ledMode = modelData.value;
                        root.setEffect(modelData.arg, root.colour);
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.swatches

                StyledRect {
                    id: swatch

                    required property string modelData
                    required property int index
                    readonly property bool selected: root.colour.toLowerCase() === modelData.toLowerCase()

                    Layout.fillWidth: true
                    implicitHeight: Tokens.padding.large * 2
                    radius: Tokens.rounding.full
                    color: "#" + modelData
                    border.width: selected ? 3 : 1
                    border.color: selected ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.2)

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: swatch.index === 0
                        text: "palette"
                        color: Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.small
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setColour(swatch.modelData)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: batIcon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: root.chargeLimit < 100 ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: batIcon

                    anchors.centerIn: parent
                    text: "battery_saver"
                    color: root.chargeLimit < 100 ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Battery charge limit")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.chargeLimit > 0 ? qsTr("Stops charging at %1%").arg(root.chargeLimit) : "?"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: root.limits

                Choice {
                    required property int modelData

                    text: `${modelData}%`
                    checked: root.chargeLimit === modelData
                    onClicked: root.setLimit(modelData)
                }
            }

            Choice {
                text: qsTr("Full once")
                onClicked: root.exec(["asusctl", "battery", "oneshot"])
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
