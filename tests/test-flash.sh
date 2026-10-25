#!/bin/bash
# Fault injection uses regular files, never real device partitions.
set -eo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
. "$ROOT/tools/sashimi-flash.sh"
ui_print() { printf '%s\n' "$*" >> "$WORK/messages"; }
sashimi_partition_size() { test -f "$1" && wc -c < "$1"; }
blockdev() { test "${DENY_WRITES:-0}" != 1; }
df() { echo 'Unexpected persistent storage probe' >&2; return 1; }
stat() { echo 'Unexpected filesystem probe' >&2; return 1; }
dd() {
  local arg out
  for arg in "$@"; do case "$arg" in of=*) out=${arg#of=};; esac; done
  [ "${FAIL_WRITE:-0}" != 1 ] || return 1
  echo write >> "$WORK/writes"
  command dd "$@" 2>/dev/null || return 1
  if [ "${CORRUPT_WRITE:-0}" = 1 ]; then
    printf X | command dd of="$out" bs=1 seek=1 conv=notrunc 2>/dev/null
  fi
}
reset_fixture() {
  FAIL_WRITE=0 CORRUPT_WRITE=0 DENY_WRITES=0
  head -c 65536 /dev/urandom > "$WORK/boot_a"
  head -c 12345 /dev/urandom > "$WORK/new.img"
  head -c 65536 /dev/urandom > "$WORK/exact.img"
  head -c 65537 /dev/urandom > "$WORK/oversize.img"
  : > "$WORK/empty.img"
  : > "$WORK/writes"
  ORIGINAL=$(sashimi_sha256 "$WORK/boot_a")
}
must_fail() { if "$@"; then echo "Unexpected success: $*" >&2; exit 1; fi; }
unchanged() { test "$(sashimi_sha256 "$WORK/boot_a")" = "$ORIGINAL"; test ! -s "$WORK/writes"; }
reset_fixture
sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" pad
test "$(sashimi_readback_hash "$WORK/boot_a" 12345)" = "$(sashimi_sha256 "$WORK/new.img")"
test "$(tail -c 53191 "$WORK/boot_a" | sha256sum)" = "$(head -c 53191 /dev/zero | sha256sum)"
test "$(wc -c < "$WORK/boot_a")" = 65536
echo 'PASS: finite padded write and readback without persistent storage'
reset_fixture
old_tail=$(tail -c 53191 "$WORK/boot_a" | sha256sum)
sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" raw
test "$old_tail" = "$(tail -c 53191 "$WORK/boot_a" | sha256sum)"
sashimi_flash_image "$WORK/exact.img" "$WORK/boot_a" pad
test "$(sashimi_sha256 "$WORK/boot_a")" = "$(sashimi_sha256 "$WORK/exact.img")"
echo 'PASS: raw DTBO tail and exact-capacity image preserved'
reset_fixture
must_fail sashimi_flash_image "$WORK/oversize.img" "$WORK/boot_a" pad
must_fail sashimi_flash_image "$WORK/empty.img" "$WORK/boot_a" pad
must_fail sashimi_flash_image "$WORK/new.img" "$WORK/missing_a" pad
must_fail sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" invalid
DENY_WRITES=1
must_fail sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" pad
unchanged
echo 'PASS: invalid images, destinations and read-only targets fail before writing'
reset_fixture
FAIL_WRITE=1
must_fail sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" pad
reset_fixture
CORRUPT_WRITE=1
must_fail sashimi_flash_image "$WORK/new.img" "$WORK/boot_a" pad
echo 'PASS: write failure and silent corruption detected'
bash -n "$ROOT/anykernel.sh" "$ROOT/tools/ak3-core.sh" "$ROOT/tools/sashimi-flash.sh" "$ROOT/META-INF/com/google/android/update-binary" "$ROOT/place-modules.sh" "$ROOT/resize_vendor.sh"
echo 'PASS: shell syntax including restored recovery helpers'
