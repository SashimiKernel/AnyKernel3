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
supported.versions=16.1-17
'; }

### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

if [ "$(file_getprop $AKHOME/anykernel.sh do.systemless)" == 1 ]; then
  if [ ! -f /data/adb/ksud ]; then
    LIBKSUD=$(find /data/app -name 'libksud.so' 2>/dev/null | head -1);

    if [ -z "$LIBKSUD" ]; then
      ui_print " ";
      ui_print " " "ERROR: do.systemless mode is enabled!";
      ui_print " " "ERROR: /data/adb/ksud was not found!";
      ui_print " " "ERROR: libksud.so was not found in /data/app!";
      ui_print " " "Rooted or not-rooted device doesn't matter: manager is required, Install it and try again.";
      ui_print " ";
      abort "abort";
    fi;
  fi;
fi;

# boot install
dump_boot;

write_boot;
## end boot install

## vendor_boot files attributes
vendor_boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# vendor_boot shell variables
BLOCK=vendor_boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# reset for vendor_boot patching
reset_ak;

# vendor_boot install
dump_boot;
if [ -d "vendor_ramdisk/lib/modules" ]; then
  rm -rf "$RAMDISK/lib/modules";
  mkdir -p "$RAMDISK/lib/modules";

  cp -af vendor_ramdisk/lib/modules/. "$RAMDISK/lib/modules/";
fi;

write_boot;
ui_print "[=] Kernel flashed successfully!";
ui_print "[=] Arigato for using Sashimi!! :3";
## end vendor_boot install
