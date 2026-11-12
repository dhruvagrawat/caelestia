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

# Strips: MAC|protocol. Protocols:
#   leddmx: LEDDMX-0x controllers ("LED Lamp" app), char ffe1, 7B .. BF frames, RGB
#   mrstar: "GATT--DEMO" controllers ("Mr. Star" app), char fff3, BC op len .. 55 frames, HSV
STRIPS=(
    "41:42:7B:F8:94:5B|leddmx"  # 1: LEDDMX-03-945B
    "E4:98:BB:D8:D2:91|mrstar"  # 2: GATT--DEMO (Mr. Star)
)

# RGB hex -> "hue sat*1000 value*1024" for Mr. Star
hsv() {
    awk -v h="$1" 'function hx(s){return index("0123456789abcdef",substr(s,1,1))*16+index("0123456789abcdef",substr(s,2,1))-17}
    BEGIN { h=tolower(h); r=hx(substr(h,1,2))/255; g=hx(substr(h,3,2))/255; b=hx(substr(h,5,2))/255;
        mx=r; if(g>mx)mx=g; if(b>mx)mx=b; mn=r; if(g<mn)mn=g; if(b<mn)mn=b; d=mx-mn;
        if(d==0)H=0; else if(mx==r)H=60*(((g-b)/d)%6); else if(mx==g)H=60*((b-r)/d+2); else H=60*((r-g)/d+4);
        if(H<0)H+=360; S=(mx==0)?0:d/mx;
        printf "%d %d %d\n", H+0.5, S*1000+0.5, mx*1024+0.5 }'
}

u16() { printf '0x%02x 0x%02x' $(($1 >> 8)) $(($1 & 255)); }

# Prints one frame per line
frame() { # protocol action args...
    local proto=$1 action=$2
    case "$proto:$action" in
        mrstar:colour)
            read -r H S V < <(hsv "$3")
            [ "$V" -lt 10 ] && V=10
            echo "0xbc 0x04 0x06 $(u16 "$H") $(u16 "$S") 0x00 0x00 0x55"
            echo "0xbc 0x05 0x06 $(u16 "$V") 0x00 0x00 0x00 0x00 0x55"
            ;;
        mrstar:power) [ "$3" = on ] && echo '0xbc 0x01 0x01 0x01 0x55' || echo '0xbc 0x01 0x01 0x00 0x55' ;;
        leddmx:colour) printf '0x7b 0xff 0x07 0x%s 0x%s 0x%s 0x00 0xff 0xbf\n' "${3:0:2}" "${3:2:2}" "${3:4:2}" ;;
        leddmx:power) [ "$3" = on ] && echo '0x7b 0x04 0x04 0x01 0xff 0xff 0xff 0xff 0xbf' || echo '0x7b 0x04 0x04 0x00 0xff 0xff 0xff 0xff 0xbf' ;;
        *) return 1 ;;
    esac
}

char_uuid() { case $1 in leddmx) echo 0000ffe1-0000-1000-8000-00805f9b34fb ;; mrstar) echo 0000fff3-0000-1000-8000-00805f9b34fb ;; esac; }
write_opts() { case $1 in mrstar) echo '1 type s command' ;; *) echo 0 ;; esac; }

send() { # strip-index action args...
    local entry=${STRIPS[$(($1 - 1))]}
    [ -n "$entry" ] || return 1
    local mac=${entry%%|*} proto=${entry##*|}
    local bytes; bytes=$(frame "$proto" "$2" "$3") || return 1
    local dev=/org/bluez/hci0/dev_${mac//:/_}

    local was_connected=0
    bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes" && was_connected=1
    if [ $was_connected = 0 ]; then
        # The controller must have been seen recently for BlueZ to connect
        timeout 6 bluetoothctl connect "$mac" >/dev/null 2>&1 || {
            timeout 8 bluetoothctl --timeout 6 scan le >/dev/null 2>&1
            timeout 15 bluetoothctl connect "$mac" >/dev/null 2>&1
        } || return 1
    fi

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

    local rc=0 line
    while read -r line; do
        [ -n "$line" ] || continue
        # shellcheck disable=SC2086
        set -- $line
        busctl --system call org.bluez "$char" org.bluez.GattCharacteristic1 WriteValue 'aya{sv}' $# "$@" $(write_opts "$proto") >/dev/null || rc=1
        sleep 0.15
    done <<< "$bytes"
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
