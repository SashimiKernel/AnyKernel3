### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
properties() { '
kernel.string=Sashimi Kernel
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=bangkk
supported.versions=16-17
'; }

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

PATCH_VENDOR=0;
[ -f dtb -o -d vendor_ramdisk -o -d vendor_patch ] && PATCH_VENDOR=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;
. "$AKHOME/tools/sashimi-common.sh";
check_android_base || exit 1;

case "$SLOT" in
  _a|_b) TARGET_SLOT=$SLOT;;
  *) abort "Invalid target slot.";;
esac;

find_partition() {
  local directory;
  for directory in /dev/block/bootdevice/by-name /dev/block/by-name; do
    if [ -b "$directory/$1$TARGET_SLOT" ]; then
      printf '%s\n' "$directory/$1$TARGET_SLOT";
      return 0;
    fi;
  done;
  return 1;
}

check_image_size() {
  local size capacity;
  [ -b "$2" ] || abort "Missing target partition: $2";
  [ -s "$1" ] || abort "Missing or empty image: $1";
  size=$(wc -c < "$1");
  capacity=$(blockdev --getsize64 "$2") || abort "Cannot read partition size: $2";
  case "$capacity" in
    ""|*[!0-9]*) abort "Invalid partition size: $2";;
  esac;
  [ "$capacity" -gt 0 -a "$size" -le "$capacity" ] || abort "Image exceeds partition size: $1";
}

stage_image() {
  dump_boot;
  repack_ramdisk;
  prepare_boot;
  check_image_size "$AKHOME/boot-new.img" "$BLOCK";
  cp -f "$AKHOME/boot-new.img" "$STAGING/$1.img" || abort "Cannot stage $1 image.";
}

vendor_boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*;
  set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

BOOT_TARGET=$(find_partition boot) || abort "Boot partition not found.";
[ "$BLOCK" = "$BOOT_TARGET" ] || abort "Boot target does not match the selected slot.";
[ -s "$AKHOME/Image" ] || abort "Kernel Image is missing or empty.";
[ "$(od -An -tx1 -j56 -N4 "$AKHOME/Image" | tr -d ' \n')" = 41524d64 ] || abort "Invalid ARM64 kernel Image.";

if [ "$PATCH_VENDOR" = 1 ]; then
  VENDOR_TARGET=$(find_partition vendor_boot) || abort "Vendor boot partition not found.";
  [ -f "$AKHOME/vendor_v3_setup" ] || abort "Unsupported vendor boot layout.";
  if [ -f "$AKHOME/vendor_boot-files/dtb" ]; then
    [ -s "$AKHOME/vendor_boot-files/dtb" ] || abort "DTB image is empty.";
  fi;
fi;

if [ -f "$AKHOME/dtbo.img" ]; then
  DTBO_TARGET=$(find_partition dtbo) || abort "DTBO partition not found.";
  check_image_size "$AKHOME/dtbo.img" "$DTBO_TARGET";
  [ "$(od -An -tx1 -N4 "$AKHOME/dtbo.img" | tr -d ' \n')" = d7b7ab1e ] || abort "Invalid DTBO image.";
fi;

for IMAGE in vendor_boot.img vendor_kernel_boot.img vendor_dlkm.img system_dlkm.img; do
  [ ! -f "$AKHOME/$IMAGE" ] || abort "Unsupported extra partition image: $IMAGE";
done;

STAGING="$AKHOME/.sashimi-prepared";
mkdir -p "$STAGING" || abort "Cannot create staging directory.";
stage_image boot;

if [ "$PATCH_VENDOR" = 1 ]; then
  BLOCK=$VENDOR_TARGET;
  reset_ak;
  [ "$SLOT" = "$TARGET_SLOT" -a "$BLOCK" = "$VENDOR_TARGET" ] || abort "Vendor boot target changed.";
  stage_image vendor_boot;
fi;

BLOCK=$BOOT_TARGET;
cp -f "$STAGING/boot.img" "$AKHOME/boot-new.img" || abort "Cannot restore prepared boot image.";
BOOT_PREPARED_FOR=$BLOCK;
flash_boot;

if [ "$PATCH_VENDOR" = 1 ]; then
  BLOCK=$VENDOR_TARGET;
  cp -f "$STAGING/vendor_boot.img" "$AKHOME/boot-new.img" || abort "Cannot restore prepared vendor boot image.";
  BOOT_PREPARED_FOR=$BLOCK;
  flash_boot;
fi;

if [ "$DTBO_TARGET" ]; then
  ui_print " " "$DTBO_TARGET";
  blockdev --setrw "$DTBO_TARGET" 2>/dev/null || abort "Cannot enable DTBO writes.";
  dd if="$AKHOME/dtbo.img" of="$DTBO_TARGET" bs=1048576 conv=fsync || abort "Flashing DTBO failed.";
else
  ui_print " " "DTBO image not included; keeping current DTBO.";
fi;
sync;
rm -rf "$STAGING";
ui_print "[=] Kernel flashed successfully!";
ui_print "[=] Arigato for using Sashimi!! :3";
