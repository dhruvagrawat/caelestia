#!/usr/bin/env bash
# Wallpaper picker: shows a rofi grid of wallpaper previews and applies the
# chosen one (via awww) to the monitor that is currently focused only.

WALL_DIR="${WALL_DIR:-$HOME/Dhruv/Walls}"
THUMB_DIR="$HOME/.cache/wall-thumbs"
THEME="$(dirname "$(readlink -f "$0")")/wallpaper.rasi"

# Monitor the picker was opened on
MONITOR=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
[ -z "$MONITOR" ] && exit 1

# Make sure the wallpaper daemon is running
if ! pgrep -x awww-daemon >/dev/null; then
    setsid -f awww-daemon >/dev/null 2>&1
    sleep 0.5
fi

mkdir -p "$THUMB_DIR"
shopt -s nullglob nocaseglob
images=("$WALL_DIR"/*.{jpg,jpeg,png,webp,gif})

# Generate missing thumbnails
for img in "${images[@]}"; do
    thumb="$THUMB_DIR/$(basename "$img").png"
    [ -f "$thumb" ] || magick "$img[0]" -resize 500x214^ -gravity center -extent 500x214 "$thumb"
done

SELECTED=$(for img in "${images[@]}"; do
    name=$(basename "$img")
    printf '%s\0icon\x1f%s\n' "$name" "$THUMB_DIR/$name.png"
done | rofi -dmenu -i -show-icons -theme "$THEME" -p "󰸉 $MONITOR")

[ -z "$SELECTED" ] && exit 0

awww img -o "$MONITOR" "$WALL_DIR/$SELECTED" \
    --transition-type grow \
    --transition-duration 1.2
