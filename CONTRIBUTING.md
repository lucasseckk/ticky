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
- Vor jedem Pull Request: `zsh check.command` muss grün sein, die App muss bauen und starten.
- Kleine, vollständige Änderungen statt großer Umbauten; neue Logik bekommt einen Check in `Checks/StoreCheck.swift`.
- Keine Tokens, Passwörter oder persönlichen Daten in Code, Issues oder Screenshots. GitHub-Zugriff läuft ausschließlich über die `gh`-CLI.

## Coding-Agents

Regeln für Claude Code, Codex & Co. stehen in [`AGENTS.md`](AGENTS.md). Aufgaben für Agents sind Issues mit dem Label `agent`.
