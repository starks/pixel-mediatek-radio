#!/system/bin/sh
set -eu
base=/sys/kernel/tracing
name=pixel_mtk_radio_$$
instance=$base/instances/$name
group=$instance/events/$name
vendor=vendor.mediatek.hardware.mtkradioex.network.IMtkRadioExNetwork/slot1
daemon=/vendor/lib64/libmtkmipc-ril.so
expected=1600b8d2b3f7878e96b65ee9adccb3637841b9e96f58a9b6730b1c31ef48472f
usage() {
  printf '%s\n' 'Usage: pixel-radio.sh read|restore lte|nr' '       pixel-radio.sh lock lte|nr BAND [BAND ...]'
}
case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac
[ "$#" -ge 2 ] || { usage >&2; exit 2; }
mode=$1
rat=$2
shift 2
case "$rat" in
  nr) words=32; fields="bank_a bank_b"; file=baseline; radio=NR; max_band=1024 ;;
  lte) words=8; fields=bank_a; file=baseline-lte; radio=LTE; max_band=256 ;;
  *) usage >&2; exit 2 ;;
esac
case "$mode" in
  read|restore) [ "$#" -eq 0 ] || { usage >&2; exit 2; } ;;
  lock)
    [ "$#" -ge 1 ] && [ "$#" -le 100 ] || { usage >&2; exit 2; }
    for band in "$@"; do
      case "$band" in
        ''|0*|*[!0-9]*) echo "Invalid band: $band" >&2; exit 2 ;;
      esac
      [ "${#band}" -le 4 ] && [ "$band" -le "$max_band" ] || { echo "Band out of range: $band" >&2; exit 2; }
    done
    ;;
  *) usage >&2; exit 2 ;;
esac
requested="$*"
[ "$(id -u)" = 0 ] || { echo "Root is required" >&2; exit 1; }
stub=/vendor/lib64/vendor.mediatek.hardware.mtkradioex.network-V1-ndk.so
stub_hash=cdb02c674a5a55955709e080c53f92be50e0695748bbb4f9c2182cc902851183
if [ "$(getprop ro.product.device)" != kodiak ] ||
   [ "$(sha256sum "$daemon" | cut -d ' ' -f1)" != "$expected" ] ||
   [ "$(sha256sum "$stub" | cut -d ' ' -f1)" != "$stub_hash" ]; then
  echo "Unsupported device or radio firmware" >&2
  exit 1
fi
[ "$(settings get global multi_sim_data_call)" = 1 ] ||
  { echo "Default data subscription differs from the tested configuration" >&2; exit 1; }
service call "$vendor" 16777215 | grep -q '00000000 00000001' ||
  { echo "MediaTek radio Binder interface version 1 unavailable" >&2; exit 1; }
state=/data/adb/local.pixel.nrlock
umask 077
mkdir -p "$state"
saved=$state/$file
dirty=0
created=0

add_probe() {
  spec="p:$name/$1 $daemon:$2"
  i=0
  while [ "$i" -lt "$words" ]; do
    spec="$spec w$i=+$((4*i))(%$3):x32"
    i=$((i+1))
  done
  printf '%s\n' "$spec" >> "$base/uprobe_events"
  echo 1 > "$group/$1/enable"
}

snapshot() {
  : > "$instance/trace"
  service call "$vendor" 11 i32 "$1" i32 0 >/dev/null || return 1
  attempt=0
  while [ "$attempt" -lt 36 ]; do
    data=$(sed -n 's/.* bank_\([ab]\): ([^)]*) /\1 /p' "$instance/trace")
    if [ "$(printf '%s\n' "$data" | grep -c '^a ')" -eq 1 ] &&
       { [ "$rat" = lte ] || [ "$(printf '%s\n' "$data" | grep -c '^b ')" -eq 1 ]; }; then
      printf '%s\n' "$data"
      return 0
    fi
    sleep 0.25
    attempt=$((attempt+1))
  done
  return 1
}

bands() {
  if [ "$rat" = lte ] && [ "$2" = b ]; then return 0; fi
  printf '%s\n' "$1" | awk '
    $1 == bank && NF == words + 1 {
      for (i=2; i<=NF; i++) {
        v=0
        value=substr($i,index($i,"=0x")+3)
        for(j=1; j<=length(value); j++) {
          d=index("0123456789abcdef",substr(value,j,1))-1
          if (d<0) exit 2
          v=v*16+d
        }
        for(b=0; b<32; b++) {
          if (v%2) printf "%d ", (i-2)*32+b+1
          v=int(v/2)
        }
      }
      found=1
    }
    END { if (!found) exit 1 }
  ' bank="$2" words="$words"
}

change() {
  serial=$1
  if [ "$rat" = lte ]; then
    lte_change
    return
  fi
  set -- i32 "$serial"
  for list in "$add_a" "$remove_a" "$add_b" "$remove_b"; do
    count=0
    for band in $list; do count=$((count+1)); done
    set -- "$@" i32 "$count"
    for band in $list; do set -- "$@" i32 "$band"; done
  done
  service call "$vendor" 55 "$@" i32 0 >/dev/null
}

# The LTE Binder setter edits one band bit per request. Confirm each write
# before the next read-modify-write can start on the modem.
lte_change() {
  for enabled in 1 0; do
    if [ "$enabled" = 1 ]; then list=$add_a; else list=$remove_a; fi
    for band in $list; do
      serial=$((serial+1))
      service call "$vendor" 49 i32 "$serial" i32 "$band" i32 "$enabled" i32 0 >/dev/null || return 1
      attempt_lte=0
      while :; do
        lte_read=$(snapshot "$((serial+5000))") || return 1
        active=$(bands "$lte_read" a) || return 1
        case " $active" in *" $band "*) present=1 ;; *) present=0 ;; esac
        if [ "$present" = "$enabled" ]; then break; fi
        attempt_lte=$((attempt_lte+1))
        [ "$attempt_lte" -lt 3 ] || { echo "LTE B$band readback did not match the request"; return 1; }
      done
    done
  done
}
serving() {
  dumpsys telephony.registry | grep 'mPhysicalChannelConfigs' |
    grep -oE 'PrimaryServing|SecondaryServing|mNetworkType=[A-Z0-9_]+|mDownlinkChannelNumber=[0-9]+|mBand=[0-9]+' |
    tr '\n' ' '
  echo
}

difference() {
  printf "%s\n%s\n" "$1" "$2" | awk 'NR==1 {for(i=1;i<=NF;i++) present[$i]=1} NR==2 {for(i=1;i<=NF;i++) if(!($i in present)) printf "%s ", $i}'
}

restore() {
  echo 'Restoring original masks'
  wanted_a=$(bands "$baseline" a) || return 1
  wanted_b=$(bands "$baseline" b) || return 1
  for attempt in 1 2; do
    current=$(snapshot "$((1879048260+attempt))") || continue
    current_a=$(bands "$current" a) || continue
    current_b=$(bands "$current" b) || continue
    if [ "$current" != "$baseline" ]; then
      add_a=$(difference "$current_a" "$wanted_a")
      remove_a=$(difference "$wanted_a" "$current_a")
      add_b=$(difference "$current_b" "$wanted_b")
      remove_b=$(difference "$wanted_b" "$current_b")
      change "$((1879048240+attempt))" || true
      sleep 2
    fi
    actual=$(snapshot "$((1879048250+attempt))") || actual=''
    if [ "$actual" = "$baseline" ]; then
      if [ "$mode" = restore ] || [ "$created" = 1 ]; then rm -f "$saved" || return 1; fi
      dirty=0
      echo 'RESTORED'
      return 0
    fi
    printf 'Restore readback %s\n' "$actual"
  done
  echo 'RESTORE NOT VERIFIED' >&2
  return 1
}

cleanup() {
  rc=$?
  trap - EXIT HUP INT TERM
  if [ "$dirty" = 1 ]; then restore || rc=1; fi
  for field in $fields; do
    if [ -e "$group/$field/enable" ]; then echo 0 > "$group/$field/enable" || true; fi
  done
  rmdir "$instance" || true
  for field in $fields; do printf '%s\n' "-:$name/$field" >> "$base/uprobe_events" || true; done
  exit "$rc"
}
# Hold the file lock through trace cleanup and any rollback.
run_locked() {
  flock -n 9 || { echo "Another radio operation is running"; exit 1; }
  mkdir "$instance"
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM
  # These parser offsets are specific to the pinned radio library.
  if [ "$rat" = lte ]; then
    add_probe bank_a 0x451c88 x0
  else
    add_probe bank_a 0x451cf4 x21
    add_probe bank_b 0x451f8c x8
  fi
  baseline=$(snapshot 1879048221)
  check=$(snapshot 1879048222)
  [ "$baseline" = "$check" ] || { echo "Modem masks changed during readback"; exit 1; }
  current_a=$(bands "$baseline" a)
  current_b=$(bands "$baseline" b)
  original=$baseline
  if [ -f "$saved" ]; then original=$(cat "$saved"); fi
  original_a=$(bands "$original" a)
  original_b=$(bands "$original" b)
  if [ "$mode" = read ]; then
    printf 'BASELINE_A %s\nCURRENT_A %s\n' "$original_a" "$current_a"
    if [ "$rat" = nr ]; then
      printf 'BASELINE_B %s\nCURRENT_B %s\n' "$original_b" "$current_b"
    fi
    if [ -f "$saved" ]; then echo 'RESTORE_POINT_PRESENT'; fi
    exit 0
  fi
  if [ "$mode" = restore ]; then
    if [ -f "$saved" ]; then
      baseline=$original
      restore
    else
      echo 'NO_RESTORE_POINT'
    fi
    exit 0
  fi
  [ "$mode" = lock ]
  unknown=$(difference "$original_a $original_b" "$requested")
  [ -z "$unknown" ] || { echo "Bands absent from the baseline: $unknown" >&2; exit 2; }
  intersection() {
    printf '%s\n%s\n' "$1" "$2" | awk 'NR==1 {for(i=1;i<=NF;i++) keep[$i]=1} NR==2 {for(i=1;i<=NF;i++) if($i in keep) printf "%s ", $i}'
  }
  target_a=$(intersection "$requested" "$original_a")
  target_b=$(intersection "$requested" "$original_b")
  [ -n "$target_a" ] && { [ "$rat" = lte ] || [ -n "$target_b" ]; } || { echo "The selection leaves one modem mask empty"; exit 1; }
  if [ ! -e "$saved" ]; then
    printf '%s\n' "$baseline" > "$saved.tmp"
    mv "$saved.tmp" "$saved"
    sync
    created=1
  fi
  dirty=1
  add_a=$(difference "$current_a" "$target_a")
  remove_a=$(difference "$target_a" "$current_a")
  add_b=$(difference "$current_b" "$target_b")
  remove_b=$(difference "$target_b" "$current_b")
  change 1879048223
  for attempt in 1 2 3; do
    sleep 2
    verified=$(snapshot "$((1879048230+attempt))") || continue
    if [ "$(bands "$verified" a)" = "$target_a" ] && [ "$(bands "$verified" b)" = "$target_b" ]; then
      dirty=0
      observed=$(serving)
      primary=$(printf '%s\n' "$observed" | sed -nE "s/.*PrimaryServing mNetworkType=$radio mDownlinkChannelNumber=[0-9]+ mBand=([0-9]+).*/\1/p")
      case " $requested " in
        *" ${primary:-unavailable} "*) printf 'ATTACHED %s\n' "$primary" ;;
        *) echo 'MASK_ONLY' ;;
      esac
      exit 0
    fi
  done
  echo "The modem did not report the requested masks"
  exit 1
}
run_locked 9>"$state/operation.lock"
