#!/usr/bin/env bash
# Control Bluetooth LED strips (fork only).
#
#   ledstrip.sh colour RRGGBB [N]   set colour on strip N, or on every synced strip
#   ledstrip.sh power on|off [N]    power strip N, or every synced strip
#   ledstrip.sh sync N on|off       mark strip N as synced with the keyboard colour
#   ledstrip.sh status              print "N synced|off configured|missing" per strip
#
# Connects only for the write, then disconnects, so the phone app can still connect.

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/ledstrips"
mkdir -p "$STATE"

# Strips: MAC|protocol. Protocols: leddmx (LEDDMX-0x, ffe1, 7B..BF frames)
STRIPS=(
    "41:42:7B:F8:94:5B|leddmx"  # 1: LEDDMX-03-945B
    ""                          # 2: not identified yet
)

frame() { # protocol action args...
    local proto=$1 action=$2
    case "$proto:$action" in
        leddmx:colour) printf '0x7b 0xff 0x07 0x%s 0x%s 0x%s 0x00 0xff 0xbf' "${3:0:2}" "${3:2:2}" "${3:4:2}" ;;
        leddmx:power) [ "$3" = on ] && echo '0x7b 0x04 0x04 0x01 0xff 0xff 0xff 0xff 0xbf' || echo '0x7b 0x04 0x04 0x00 0xff 0xff 0xff 0xff 0xbf' ;;
        *) return 1 ;;
    esac
}

char_uuid() { case $1 in leddmx) echo 0000ffe1-0000-1000-8000-00805f9b34fb ;; esac; }

send() { # strip-index action args...
    local entry=${STRIPS[$(($1 - 1))]}
    [ -n "$entry" ] || return 1
    local mac=${entry%%|*} proto=${entry##*|}
    local bytes; bytes=$(frame "$proto" "$2" "$3") || return 1
    local dev=/org/bluez/hci0/dev_${mac//:/_}

    local was_connected=0
    bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && was_connected=1
    [ $was_connected = 1 ] || timeout 12 bluetoothctl connect "$mac" >/dev/null 2>&1 || return 1

    # Find the write characteristic by UUID (paths can change between connections)
    local char="" uuid; uuid=$(char_uuid "$proto")
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        for c in $(busctl --system tree org.bluez 2>/dev/null | grep -o "$dev/service[0-9a-f]*/char[0-9a-f]*$"); do
            busctl --system get-property org.bluez "$c" org.bluez.GattCharacteristic1 UUID 2>/dev/null | grep -q "$uuid" && char=$c
        done
        [ -n "$char" ] && break
        sleep 0.3
    done
    [ -n "$char" ] || return 1

    # shellcheck disable=SC2086
    busctl --system call org.bluez "$char" org.bluez.GattCharacteristic1 WriteValue 'aya{sv}' 9 $bytes 0 >/dev/null
    local rc=$?
    [ $was_connected = 1 ] || bluetoothctl disconnect "$mac" >/dev/null 2>&1
    return $rc
}

targets() { # explicit strip, or all synced strips
    if [ -n "$1" ]; then echo "$1"; return; fi
    for i in "${!STRIPS[@]}"; do [ -f "$STATE/$((i + 1)).sync" ] && echo $((i + 1)); done
}

case $1 in
colour)
    hex=${2#\#}
    for n in $(targets "$3"); do send "$n" power on && send "$n" colour "$hex" & done
    wait
    ;;
power)
    for n in $(targets "$3"); do send "$n" power "$2" & done
    wait
    ;;
sync)
    if [ "$3" = on ]; then touch "$STATE/$2.sync"; else rm -f "$STATE/$2.sync"; fi
    ;;
status)
    for i in "${!STRIPS[@]}"; do
        n=$((i + 1))
        s=off; [ -f "$STATE/$n.sync" ] && s=synced
        c=missing; [ -n "${STRIPS[$i]}" ] && c=configured
        echo "$n $s $c"
    done
    ;;
*)
    echo "usage: $0 colour RRGGBB [N] | power on|off [N] | sync N on|off | status" >&2
    exit 1
    ;;
esac
