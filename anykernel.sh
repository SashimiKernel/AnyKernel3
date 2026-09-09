### AnyKernel3 Ramdisk Mod Script

properties() { '
kernel.string=Sashimi-Kernel
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=bangkk
supported.versions=16.1-17
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

## AnyKernel boot install
ui_print "[#] Flashing Kernel...";
dump_boot;
flash_boot;

ui_print "[=] Kernel flashed successfully!";
ui_print "[=] Arigato for using Sashimi!! :3";
