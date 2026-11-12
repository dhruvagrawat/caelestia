#!/usr/bin/env bash
# Builds ~/.config/quickshell/caelestia as a thin overlay over the packaged shell.
# Everything is a symlink to /etc/xdg/quickshell/caelestia, except:
#   - files patched below (copied from the package, then edited)
#   - extra files added from this folder (symlinked)
# Package updates flow through the symlinks. If any patch can't be applied
# (upstream changed that file), nothing is installed and the stock shell is used.
#
# Usage: install.sh [--restart]   |   install.sh --remove

set -euo pipefail

SRC=/etc/xdg/quickshell/caelestia
DST="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia"
HERE="$(dirname "$(readlink -f "$0")")"

# Files we patch (relative to SRC)
PATCHED=(
    modules/utilities/Content.qml
    modules/bar/popouts/AudioPopout.qml
)
# Files we add: "<file in this folder>:<path in overlay>"
ADDED=(
    AsusCard.qml:modules/utilities/cards/AsusCard.qml
    AppStreams.qml:modules/bar/popouts/AppStreams.qml
)

restart_shell() {
    caelestia shell -k >/dev/null 2>&1 || true
    sleep 1
    pkill -x -f "qs -c caelestia -n -d" 2>/dev/null || true
    sleep 0.5
    setsid -f caelestia shell -d >/dev/null 2>&1
    # Keep awake is on by default (see hypr/hyprland/personal.lua); restore it after restart
    setsid -f sh -c 'for i in $(seq 30); do qs -c caelestia ipc call idleInhibitor enable 2>/dev/null && exit; sleep 1; done' >/dev/null 2>&1
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

# Paths that must be real (not symlinked): every patched/added file and its parent dirs
declare -A KEEP=()
mark_keep() {
    local p=$1
    while [ "$p" != "." ]; do KEEP[$p]=1; p=$(dirname "$p"); done
}
for f in "${PATCHED[@]}"; do mark_keep "$f"; done
for a in "${ADDED[@]}"; do mark_keep "${a#*:}"; done

# Mirror SRC/rel into TMP/rel: symlink everything not in KEEP, recurse into kept dirs
mirror() {
    local rel=$1
    mkdir -p "$TMP/$rel"
    for entry in "$SRC/$rel"/* "$SRC/$rel"/.[!.]*; do
        [ -e "$entry" ] || continue
        local child=${entry#"$SRC/"}
        child=${child#./}
        if [ -n "${KEEP[$child]:-}" ]; then
            [ -d "$entry" ] && mirror "$child"
        else
            ln -s "$entry" "$TMP/$child"
        fi
    done
}

# patch <rel path> <perl program that must make exactly N substitutions> <N>
patch_file() {
    local rel=$1 prog=$2 want=$3
    WANT=$want perl -0pe "$prog"' END { exit($n == $ENV{WANT} ? 0 : 1) }' "$SRC/$rel" > "$TMP/$rel" || {
        echo "Could not patch $rel (upstream changed it). Using stock shell." >&2
        return 1
    }
}

TMP="$DST.tmp.$$"
rm -rf "$TMP"
trap 'rm -rf "$TMP"' EXIT
mirror .
for a in "${ADDED[@]}"; do ln -s "$HERE/${a%%:*}" "$TMP/${a#*:}"; done

ok=1

# Utilities popup: add the ASUS card at the end of the cards column
patch_file modules/utilities/Content.qml '
    my $card = "\n\n        AsusCard {\n            id: asusCard\n\n            Layout.fillWidth: true\n        }";
    $n += s|(readonly property real nonAnimHeight: [^\n]*)|$1 + asusCard.implicitHeight + layout.spacing|;
    $n += s|(\n        \})(\n    \}\n\n    RecordingDeleteModal \{)|$1$card$2|;
' 2 || ok=0

# Bar audio popout: add per-app volume + output routing above "Open settings"
patch_file modules/bar/popouts/AudioPopout.qml '
    my $apps = "        AppStreams {\n            Layout.fillWidth: true\n            Layout.topMargin: Tokens.spacing.medium\n        }\n\n";
    $n += s|(\n)(        IconTextButton \{\n)|$1$apps$2|;
' 1 || ok=0

if [ $ok = 0 ]; then
    remove_overlay
    exit 1
fi

touch "$TMP/.caelestia-overlay"
remove_overlay
mv "$TMP" "$DST"
trap - EXIT
echo "Overlay installed at $DST"

[ "${1:-}" = "--restart" ] && restart_shell
exit 0
