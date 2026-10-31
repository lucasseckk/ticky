# Mitwirken an Ticky

Danke fürs Mitmachen! Ticky ist eine native SwiftUI-App ohne externe Abhängigkeiten – so soll es bleiben.

## Loslegen

```bash
git clone https://github.com/lucasseckk/ticky.git
cd ticky
zsh check.command          # Regressionstests (ohne Netzwerk)
zsh build.command --open   # bauen, nach ~/Applications installieren und starten
```

Vor einem Neubau eine laufende Instanz mit `pkill -x Ticky` beenden.

## Arbeitsweise

- Jede Änderung hat ein GitHub-Issue im Format `[P<Priorität>-<laufende Nr>] Titel` (P1 = dringend … P3 = später).
- Gearbeitet wird auf eigenen Branches (`feature/<issue>-…`, `fix/<issue>-…`, `docs/<issue>-…`). Commits verweisen mit `Refs #N` / `Closes #N` auf das Issue, gemergt wird über Pull Requests.
- Vor jedem Pull Request: `zsh check.command` muss grün sein, die App muss bauen und starten. GitHub Actions führt Checks und Build bei jedem Pull Request aus.
- Release: Tag `vX.Y.Z` auf einen Commit von `main` pushen. Der Workflow prüft, dass der Commit auf `main` liegt, führt `check.command` aus, baut `Ticky.zip` (Apple Silicon und Intel) und veröffentlicht es mit `install.sh` (fest auf dieses Release und diesen Commit) und `SHA256SUMS`. Releases nie von Hand hochladen – so landen keine lokalen, ungeprüften Änderungen darin.
- Signieren und Notarisieren (#124): Sind die Repository-Secrets `MACOS_CERTIFICATE_P12` (Developer-ID-Application-Zertifikat als Base64-`.p12`), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` (z. B. `Developer ID Application: Name (TEAMID)`), `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` und `NOTARY_PASSWORD` (app-spezifisches Passwort) gesetzt, signiert der Release-Workflow mit Hardened Runtime, notarisiert und stapelt das Ticket. Ohne Secrets bleibt es bei der ad-hoc-Signatur. Die Secrets erreichen nur Tag-Builds, nie Pull Requests.
- Kleine, vollständige Änderungen statt großer Umbauten; neue Logik bekommt einen Check in `Checks/StoreCheck.swift`.
- Texte schreibst du auf Deutsch, die englische Übersetzung kommt nach `Resources/Localizable.en.json`. Texte, die als `String` weitergereicht werden (Toasts, Fehler, Labels), mit `String(localized: "…")` markieren. `check.command` meldet fehlende und nicht mehr benutzte Übersetzungen.
- Keine Tokens, Passwörter oder persönlichen Daten in Code, Issues oder Screenshots. GitHub-Zugriff läuft ausschließlich über die `gh`-CLI.
- Sicherheitslücken nicht als Issue oder Pull Request melden, sondern vertraulich nach [`SECURITY.md`](SECURITY.md).

## Coding-Agents

Regeln für Claude Code, Codex & Co. stehen in [`AGENTS.md`](AGENTS.md). Aufgaben für Agents sind Issues mit dem Label `agent`.
