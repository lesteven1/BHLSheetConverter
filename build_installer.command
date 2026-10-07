#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
staging_root="$(/usr/bin/mktemp -d /tmp/sheet-machine-installer.XXXXXX)"
module_cache="$staging_root/clang-module-cache"
main_app="$staging_root/Sheet Machine.app"
installer_app="$staging_root/Install Sheet Machine.app"
package_folder="$staging_root/Sheet Machine Installer"
output_zip="$project_dir/Sheet Machine Installer.zip"

cleanup() {
  if [[ -d "$staging_root" && "$staging_root" == /tmp/sheet-machine-installer.* ]]; then
    /bin/rm -R "$staging_root"
  fi
}
trap cleanup EXIT

/bin/mkdir -p \
  "$module_cache" \
  "$main_app/Contents/MacOS" \
  "$installer_app/Contents/MacOS" \
  "$installer_app/Contents/Resources" \
  "$package_folder"

/bin/cp "$project_dir/app/Info.plist" "$main_app/Contents/Info.plist"
/usr/bin/env CLANG_MODULE_CACHE_PATH="$module_cache" \
  /usr/bin/xcrun swiftc \
  "$project_dir/Sources/SheetMachine/main.swift" \
  -target arm64-apple-macosx13.0 \
  -o "$main_app/Contents/MacOS/SheetMachine" \
  -framework AppKit \
  -O
/usr/bin/xattr -cr "$main_app"
/usr/bin/codesign --force --deep --sign - "$main_app"

/bin/cp "$project_dir/installer_app/Info.plist" "$installer_app/Contents/Info.plist"
/usr/bin/ditto --noqtn "$main_app" "$installer_app/Contents/Resources/Sheet Machine.app"
/usr/bin/env CLANG_MODULE_CACHE_PATH="$module_cache" \
  /usr/bin/xcrun swiftc \
  "$project_dir/Sources/SheetMachineInstaller/main.swift" \
  -target arm64-apple-macosx13.0 \
  -o "$installer_app/Contents/MacOS/SheetMachineInstaller" \
  -framework AppKit \
  -O
/usr/bin/xattr -cr "$installer_app"
/usr/bin/codesign --force --deep --sign - "$installer_app"

/usr/bin/ditto --noqtn "$installer_app" "$package_folder/Install Sheet Machine.app"
/bin/cp "$project_dir/installer_app/Read Me.txt" "$package_folder/Read Me.txt"

/usr/bin/ditto -c -k --keepParent "$package_folder" "$output_zip"

echo "Created: $output_zip"
