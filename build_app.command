#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
bundle_dir="$script_dir/dist/Sheet Machine.app"
contents_dir="$bundle_dir/Contents"
binary_dir="$contents_dir/MacOS"
module_cache="$script_dir/.build/clang-module-cache"

/bin/mkdir -p "$binary_dir" "$module_cache"
if [[ -f "$contents_dir/_CodeSignature/CodeResources" ]]; then
  /bin/unlink "$contents_dir/_CodeSignature/CodeResources"
  /bin/rmdir "$contents_dir/_CodeSignature"
fi
/bin/cp "$script_dir/app/Info.plist" "$contents_dir/Info.plist"
/usr/bin/env CLANG_MODULE_CACHE_PATH="$module_cache" \
/usr/bin/xcrun swiftc \
  "$script_dir/Sources/SheetMachine/main.swift" \
  -o "$binary_dir/SheetMachine" \
  -framework AppKit \
  -O

echo "Built: $bundle_dir"
