#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
app="dist/todo list.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ToDoList "$app/Contents/MacOS/ToDoList"
cp Info.plist "$app/Contents/Info.plist"
# Finder/FileProvider metadata can invalidate an ad-hoc app bundle signature.
xattr -cr "$app" 2>/dev/null || true
codesign --force --sign - "$app"
echo "Fertig: $PWD/$app"
if [[ "${1:-}" == "--open" ]]; then
    open "$app"
fi
