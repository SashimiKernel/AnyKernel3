### AnyKernel3 Ramdisk Mod Script

properties() { '
kernel.string=Sashimi Kernel by @MrEliteBall
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=bangkk
supported.versions=16-17
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

## AnyKernel boot install
ui_print "[#] Installing Kernel...";
dump_boot;
write_boot;

# The generated DTB and recovery ramdisk compatibility overlay live in
# vendor_boot on lisa, so switch partitions and repack that image after
# boot/dtbo are done.
BLOCK=vendor_boot;
reset_ak;

ui_print "[#] Installing dtb and recovery ramdisk compatibility...";
dump_boot;
write_boot;

ui_print "[+] Kernel flash successful!";
ui_print "[+] Arigato for using Sashimi Kernel!! :3";
## end boot install
