#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
# Installed like a normal app, so Spotlight and Launchpad find it (#86).
app="$HOME/Applications/To-Do List.app"
mkdir -p "$HOME/Applications"
rm -rf "$app" dist  # dist/ held earlier builds; a single copy keeps Spotlight unambiguous
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp .build/release/ToDoList "$app/Contents/MacOS/ToDoList"
cp Info.plist "$app/Contents/Info.plist"
# Finder/FileProvider metadata can invalidate an ad-hoc app bundle signature.
xattr -cr "$app" 2>/dev/null || true
codesign --force --sign - "$app"
echo "Fertig: $PWD/$app"
if [[ "${1:-}" == "--open" ]]; then
    open "$app"
fi
