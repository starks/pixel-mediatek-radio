#!/system/bin/sh
# SPDX-License-Identifier: MIT
set -eu

usage() {
    echo 'Usage: pixel-atci.sh read|capabilities lte|nr'
    echo '       pixel-atci.sh apply lte|nr MASKS'
    exit 2
}

[ "$#" -ge 2 ] || usage
operation=$1
case "$2" in
    lte) command=EPBSE ;;
    nr) command=EPBSEH ;;
    *) usage ;;
esac
case "$operation" in
    read) [ "$#" -eq 2 ] || usage; request="AT+$command?" ;;
    capabilities) [ "$#" -eq 2 ] || usage; request="AT+$command=?" ;;
    apply)
        [ "$#" -eq 3 ] || usage
        # Readback may contain a second NR mask. The setter takes the first four fields.
        masks=$(printf '%s\n' "$3" | awk -F, -v cmd="$command" '
            NR != 1 { invalid = 1 }
            NR == 1 && cmd == "EPBSE" {
                if (NF != 10) invalid = 1
                for (i = 1; i <= NF; i++)
                    if ($i !~ /^[0-9]+$/ || length($i) > 10 || $i + 0 > 4294967295) invalid = 1
                output = $0
            }
            NR == 1 && cmd == "EPBSEH" {
                if (NF != 4 && NF != 5) invalid = 1
                for (i = 1; i <= NF; i++) {
                    if ($i !~ /^"[0-9a-fA-F]+"$/) invalid = 1
                    digits = length($i) - 2
                    if (digits < 8 || digits > 256 || digits % 8 != 0) invalid = 1
                    if (i <= 2 && digits != 8) invalid = 1
                    if (i == 3 && digits != 24) invalid = 1
                }
                output = $1 "," $2 "," $3 "," $4
            }
            END { if (invalid || NR != 1) exit 1; print output }
        ') || { echo 'Invalid band mask fields' >&2; exit 2; }
        request="AT+$command=$masks"
        ;;
    *) usage ;;
esac

[ "$(id -u)" = 0 ] || { echo 'Root is required' >&2; exit 1; }
case "$(getprop persist.vendor.service.atci.sim)" in
    ''|0) ;;
    *) echo 'Only logical SIM slot 1 is verified' >&2; exit 1 ;;
esac
socket=/dev/socket/rild-atci
[ -S "$socket" ] || { echo 'MediaTek ATCI socket not found' >&2; exit 1; }

send_at() {
    length=$((${#1} + 1))
    high=$(printf '%03o' "$((length / 256))")
    low=$(printf '%03o' "$((length % 256))")
    # Keep the connection open while the modem sends its unframed reply.
    { printf '\000\000'; printf "\\$high\\$low"; printf '%s\r' "$1"; sleep 3; } |
        timeout 4 nc -U "$socket" | tr -d '\000\r'
}

reply=$(send_at "$request")
printf '%s\n' "$reply" | grep -qx 'OK' ||
    { printf 'ATCI request failed: %s\n' "$reply" >&2; exit 1; }
if [ "$operation" = apply ]; then
    echo 'OK'
else
    result=$(printf '%s\n' "$reply" | sed -n "s/^+$command: *//p")
    [ -n "$result" ] || { echo 'No band mask in the ATCI response' >&2; exit 1; }
    printf '%s\n' "$result"
fi
