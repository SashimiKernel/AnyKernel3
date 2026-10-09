system_prop() {
  local file key value;
  for key in "$@"; do
    for file in /system/build.prop /system/system/build.prop /system_root/system/build.prop; do
      [ -f "$file" ] || continue;
      value=$(file_getprop "$file" "$key");
      if [ -n "$value" ]; then
        printf '%s\n' "$value";
        return 0;
      fi;
    done;
  done;
  return 1;
}

check_android_base() {
  local version build_id sdk_full sdk_minor;
  version=$(system_prop ro.system.build.version.release ro.build.version.release);
  case "$version" in
    17|17.*) return 0;;
    16|16.*) ;;
    *) abort "Unsupported Android version. Android 16 QPR1+ or 17 is required."; return 1;;
  esac;
  build_id=$(system_prop ro.system.build.id ro.build.id);
  case "$build_id" in
    BP3A.*|BP4A.*) return 0;;
  esac;
  sdk_full=$(system_prop ro.system.build.version.sdk_full ro.build.version.sdk_full);
  case "$sdk_full" in
    36.*) sdk_minor=${sdk_full#36.};;
    *) sdk_minor=$(system_prop ro.system.build.version.sdk_minor ro.build.version.sdk_minor);;
  esac;
  case "$sdk_minor" in
    ""|*[!0-9]*) ;;
    *) [ "$sdk_minor" -ge 1 ] && return 0;;
  esac;
  abort "Unsupported or unidentified Android 16 base. QPR1 or newer is required.";
  return 1;
}
