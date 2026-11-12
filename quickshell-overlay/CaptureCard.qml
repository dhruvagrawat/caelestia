pragma ComponentBehavior: Bound

// Capture card for the caelestia utilities popup (fork only):
// screenshots + screen recordings saved to ~/Documents/Captures, with copy/sound options.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root

    property var screenState
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/capture.sh"
    readonly property string folder: Quickshell.env("HOME") + "/Documents/Captures"

    PersistentProperties {
        id: opts

        property bool copy: true
        property bool sound: false

        reloadableId: "captureCardOpts"
    }

    function run(kind: string, target: string): void {
        const args = [script, kind, target];
        if (opts.copy)
            args.push("--copy");
        if (opts.sound)
            args.push("--sound");
        if (screenState)
            screenState.utilities = false;
        Quickshell.execDetached(args);
    }

    implicitHeight: layout.implicitHeight + Tokens.padding.extraLargeIncreased

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

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
                implicitHeight: capIcon.implicitHeight + Tokens.padding.large

                radius: Tokens.rounding.full
                color: Recorder.running ? Colours.palette.m3error : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: capIcon

                    anchors.centerIn: parent
                    text: Recorder.running ? "radio_button_checked" : "screenshot_monitor"
                    color: Recorder.running ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Capture")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Recorder.running ? qsTr("Recording… press Stop to save") : qsTr("Saved to Documents/Captures")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }

            Choice {
                Layout.fillWidth: false
                text: qsTr("Open folder")
                onClicked: {
                    if (root.screenState)
                        root.screenState.utilities = false;
                    Quickshell.execDetached(["sh", "-c", `mkdir -p "${root.folder}" && xdg-open "${root.folder}"`]);
                }
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Choice {
                text: qsTr("Screenshot")
                onClicked: root.run("shot", "full")
            }

            Choice {
                text: qsTr("Region")
                onClicked: root.run("shot", "region")
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Choice {
                text: Recorder.running ? qsTr("Stop") : qsTr("Record")
                checked: Recorder.running
                internalChecked: checked
                onClicked: root.run("record", "full")
            }

            Choice {
                visible: !Recorder.running
                text: qsTr("Record region")
                onClicked: root.run("record", "region")
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Choice {
                text: qsTr("Copy")
                checked: opts.copy
                internalChecked: checked
                onClicked: opts.copy = !opts.copy
            }

            Choice {
                text: qsTr("Sound")
                checked: opts.sound
                internalChecked: checked
                onClicked: opts.sound = !opts.sound
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
