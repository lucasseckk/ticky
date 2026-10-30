#!/bin/zsh
# Installs Ticky: curl -fsSL https://github.com/lucasseckk/ticky/releases/latest/download/install.sh | zsh
# Builds on this Mac, so macOS does not block the app as an unknown download.
# Always builds a published release, never the moving state of main (#125).
set -euo pipefail
repo="${TICKY_REPO:-https://github.com/lucasseckk/ticky.git}"
# Filled in by the release workflow, so the installer attached to a release builds exactly that commit.
release_version=""
release_commit=""

if (( ${$(sw_vers -productVersion)%%.*} < 14 )); then
    echo "Ticky braucht macOS 14 oder neuer."; exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Ticky braucht die Command Line Tools von Apple. Das Installationsfenster öffnet sich jetzt –"
    echo "danach diesen Befehl einfach erneut ausführen."
    xcode-select --install || true
    exit 1
fi

version="${TICKY_VERSION:-$release_version}"
if [[ -z "$version" ]]; then
    version="$(curl -fsSL https://api.github.com/repos/lucasseckk/ticky/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)" || true
fi
if [[ ! "$version" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Keine gültige Ticky-Version gefunden (${version:-leer})."; exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "Lade Ticky $version …"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" "$repo" "$work/ticky"
if [[ -n "$release_commit" && "$version" == "$release_version" && "$(git -C "$work/ticky" rev-parse HEAD)" != "$release_commit" ]]; then
    echo "Der Stand von $version passt nicht zum geprüften Release – Abbruch."; exit 1
fi
echo "Baue Ticky (dauert beim ersten Mal 1–2 Minuten) …"
pkill -x Ticky 2>/dev/null || true
zsh "$work/ticky/build.command" --open
echo "Fertig: Ticky $version liegt in ~/Applications und läuft. Später starten: ⌘ Leertaste → „Ticky“."
