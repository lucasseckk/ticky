#!/bin/zsh
# Installs Ticky: curl -fsSL https://raw.githubusercontent.com/lucasseckk/ticky/main/install.sh | zsh
# Builds on this Mac, so macOS does not block the app as an unknown download.
set -euo pipefail
repo="${TICKY_REPO:-https://github.com/lucasseckk/ticky.git}"

if (( ${$(sw_vers -productVersion)%%.*} < 14 )); then
    echo "Ticky braucht macOS 14 oder neuer."; exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Ticky braucht die Command Line Tools von Apple. Das Installationsfenster öffnet sich jetzt –"
    echo "danach diesen Befehl einfach erneut ausführen."
    xcode-select --install || true
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Lade Ticky …"
git clone --quiet --depth 1 "$repo" "$work/ticky"
echo "Baue Ticky (dauert beim ersten Mal 1–2 Minuten) …"
pkill -x Ticky 2>/dev/null || true
zsh "$work/ticky/build.command" --open
echo "Fertig: Ticky liegt in ~/Applications und läuft. Später starten: ⌘ Leertaste → „Ticky“."
