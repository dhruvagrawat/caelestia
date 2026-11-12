#!/usr/bin/env bash
# Screenshots and screen recordings, saved under ~/Documents/Captures.
#
#   capture.sh shot   full|region [--copy]
#   capture.sh record full|region [--copy] [--sound]   (run again to stop)
#
# full = the focused monitor. --copy puts the screenshot image (or the
# recording file) on the clipboard as well as saving it.

SHOTS_DIR="${CAELESTIA_SCREENSHOTS_DIR:-$HOME/Documents/Captures/Screenshots}"
export CAELESTIA_RECORDINGS_DIR="${CAELESTIA_RECORDINGS_DIR:-$HOME/Documents/Captures/Recordings}"

kind=$1 target=$2
shift 2
copy=0 sound=0
for a in "$@"; do
    case $a in
        --copy) copy=1 ;;
        --sound) sound=1 ;;
    esac
done

# Let the popup close before capturing
sleep 0.4

case $kind in
shot)
    mkdir -p "$SHOTS_DIR"
    file="$SHOTS_DIR/screenshot_$(date +%Y%m%d_%H-%M-%S).png"
    if [ "$target" = region ]; then
        geom=$(slurp) || exit 0
        grim -g "$geom" "$file" || exit 1
    else
        mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
        grim -o "$mon" "$file" || exit 1
    fi
    [ $copy = 1 ] && wl-copy --type image/png < "$file"
    msg="Saved to $file"
    [ $copy = 1 ] && msg="$msg (copied)"
    notify-send -a caelestia -i "$file" "Screenshot taken" "$msg"
    ;;
record)
    mkdir -p "$CAELESTIA_RECORDINGS_DIR"
    args=()
    # Already recording -> this call stops it
    if ! pidof gpu-screen-recorder >/dev/null; then
        [ "$target" = region ] && args+=(-r slurp)
        [ $sound = 1 ] && args+=(-s)
    fi
    [ $copy = 1 ] && args+=(-c)
    exec caelestia record "${args[@]}"
    ;;
*)
    echo "usage: $0 shot|record full|region [--copy] [--sound]" >&2
    exit 1
    ;;
esac
