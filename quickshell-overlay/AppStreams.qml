pragma ComponentBehavior: Bound

// Per-app audio for the bar audio popout (fork only):
// volume slider + output device picker for every app currently playing audio.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    // Playback streams only (apps playing audio)
    readonly property var playback: [...Audio.streams].filter(n => n && n.type === PwNodeType.AudioOutStream)

    function shortName(sink: PwNode): string {
        const d = sink?.description || sink?.name || "?";
        const bracket = d.match(/\[(.+)\]\s*$/);
        return bracket ? bracket[1] : d;
    }

    spacing: Tokens.spacing.medium

    StyledText {
        text: qsTr("Apps")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    StyledText {
        visible: root.playback.length === 0
        text: qsTr("No apps playing audio")
        color: Colours.palette.m3outline
        font: Tokens.font.body.small
    }

    Repeater {
        model: root.playback

        ColumnLayout {
            id: app

            required property PwNode modelData
            readonly property PwNode target: {
                const g = [...links.linkGroups].find(g => g?.source?.id === modelData?.id) ?? Pipewire.linkGroups.values.find(g => g?.source?.id === modelData?.id);
                return g?.target ?? null;
            }

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            PwNodeLinkTracker {
                id: links

                node: app.modelData
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Audio.getStreamName(app.modelData)
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    text: app.modelData?.audio?.muted ? qsTr("muted") : `${Math.round((app.modelData?.audio?.volume ?? 0) * 100)}%`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }

            StyledSlider {
                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium * 2

                value: app.modelData?.audio?.volume ?? 0
                onInteraction: v => Audio.setStreamVolume(app.modelData, v)
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: Audio.sinks

                    TextButton {
                        id: chip

                        required property PwNode modelData

                        type: TextButton.Tonal
                        isToggle: false
                        checked: app.target?.id === modelData.id
                        internalChecked: checked
                        horizontalPadding: Tokens.padding.small
                        verticalPadding: Tokens.padding.extraSmall
                        text: root.shortName(modelData)
                        onClicked: Quickshell.execDetached(["pactl", "move-sink-input", String(app.modelData.properties["object.serial"]), modelData.name])
                    }
                }
            }
        }
    }
}
