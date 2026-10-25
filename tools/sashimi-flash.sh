# Finite writes and readback verification. No persistent storage is required.

sashimi_partition_size() {
  [ -b "$1" ] || return 1;
  blockdev --getsize64 "$1";
}

sashimi_sha256() {
  (set -o pipefail; sha256sum "$1" | awk '{print $1}');
}

sashimi_image_stream() {
  local image=$1 padding=$2;
  cat "$image" || return 1;
  [ "$padding" -eq 0 ] || head -c "$padding" /dev/zero;
}

sashimi_readback_hash() {
  (set -o pipefail; head -c "$2" "$1" | sha256sum | awk '{print $1}');
}

sashimi_flash_image() {
  local image=$1 target=$2 mode=${3:-pad} size capacity padding expected actual;
  [ -s "$image" ] || return 1;
  capacity=$(sashimi_partition_size "$target") || return 1;
  case "$capacity" in ''|*[!0-9]*) return 1;; esac;
  size=$(wc -c < "$image") || return 1;
  [ "$capacity" -gt 0 ] && [ "$size" -gt 0 ] && [ "$size" -le "$capacity" ] || return 1;
  case "$mode" in
    pad)
      padding=$((capacity - size));
      expected=$(set -o pipefail; sashimi_image_stream "$image" "$padding" | sha256sum | awk '{print $1}') || return 1;
      ;;
    raw) expected=$(sashimi_sha256 "$image") || return 1;;
    *) return 1;;
  esac;
  blockdev --setrw "$target" || return 1;
  if [ "$mode" = pad ]; then
    (set -o pipefail; sashimi_image_stream "$image" "$padding" | dd of="$target" bs=1048576 conv=notrunc,fsync) || return 1;
    actual=$(sashimi_readback_hash "$target" "$capacity") || return 1;
  else
    dd if="$image" of="$target" bs=1048576 conv=notrunc,fsync || return 1;
    actual=$(sashimi_readback_hash "$target" "$size") || return 1;
  fi;
  [ "$expected" = "$actual" ] || {
    ui_print " " "Readback verification failed: $target";
    return 1;
  };
}
