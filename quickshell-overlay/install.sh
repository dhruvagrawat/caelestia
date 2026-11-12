#!/usr/bin/env bash
# Builds ~/.config/quickshell/caelestia as a thin overlay over the packaged shell:
# everything is a symlink to /etc/xdg/quickshell/caelestia except
# modules/utilities/Content.qml (patched to add the ASUS card) and the card itself.
# Package updates flow through the symlinks. If the patch can't be applied
# (upstream changed Content.qml), the overlay is removed so the stock shell runs.
#
# Usage: install.sh [--restart]   |   install.sh --remove

set -euo pipefail

SRC=/etc/xdg/quickshell/caelestia
DST="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
HERE="$(dirname "$(readlink -f "$0")")"

restart_shell() {
    caelestia shell -k >/dev/null 2>&1 || true
    sleep 0.5
    setsid -f caelestia shell -d >/dev/null 2>&1
}

remove_overlay() {
    # Only ever delete an overlay we created
    if [ -f "$DST/.caelestia-overlay" ]; then rm -rf "$DST"; fi
}

if [ "${1:-}" = "--remove" ]; then
    remove_overlay
    echo "Overlay removed; stock shell will be used."
    restart_shell
    exit 0
fi

if [ -e "$DST" ] && [ ! -f "$DST/.caelestia-overlay" ]; then
    echo "Refusing: $DST exists and was not created by this script." >&2
    exit 1
fi

link_all_except() { # src_dir dst_dir except...
    local s=$1 d=$2; shift 2
    mkdir -p "$d"
    for entry in "$s"/* "$s"/.[!.]*; do
        [ -e "$entry" ] || continue
        local name; name=$(basename "$entry")
        local skip=0
        for ex in "$@"; do [ "$name" = "$ex" ] && skip=1; done
        [ $skip = 1 ] || ln -s "$entry" "$d/$name"
    done
}

TMP="$DST.tmp.$$"
rm -rf "$TMP"
trap 'rm -rf "$TMP"' EXIT

link_all_except "$SRC" "$TMP" modules
link_all_except "$SRC/modules" "$TMP/modules" utilities
link_all_except "$SRC/modules/utilities" "$TMP/modules/utilities" Content.qml cards
link_all_except "$SRC/modules/utilities/cards" "$TMP/modules/utilities/cards"
ln -s "$HERE/AsusCard.qml" "$TMP/modules/utilities/cards/AsusCard.qml"

# Patch Content.qml: add the card loader at the end of the cards column,
# and include it in the height used for the open/close animation.
perl -0pe '
    my $card = "\n\n        AsusCard {\n            id: asusCard\n\n            Layout.fillWidth: true\n        }";
    $n += s|(readonly property real nonAnimHeight: [^\n]*)|$1 + asusCard.implicitHeight + layout.spacing|;
    $n += s|(\n        \})(\n    \}\n\n    RecordingDeleteModal \{)|$1$card$2|;
    END { exit($n == 2 ? 0 : 1) }
' "$SRC/modules/utilities/Content.qml" > "$TMP/modules/utilities/Content.qml" || {
    echo "Could not patch Content.qml (upstream changed it). Using stock shell." >&2
    remove_overlay
    exit 1
}

touch "$TMP/.caelestia-overlay"
remove_overlay
mv "$TMP" "$DST"
trap - EXIT
echo "Overlay installed at $DST"

[ "${1:-}" = "--restart" ] && restart_shell
exit 0
