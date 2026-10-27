# To-Do List

Native macOS-Menüleisten-App für To-dos – gebaut für den Alltag zwischen **Uni und Entwicklung**.

Die App ist eine ganz normale To-do-Liste, wie man sie kennt: Aufgaben, Fälligkeiten, Erinnerungen, Gruppen. Das eigentliche Ziel geht aber darüber hinaus: Sie soll der eine Ort sein, an dem ich neben Uni-Aufgaben auch meine **Entwicklungsarbeit** im Blick habe – offene Pull Requests, Reviews, dringende Issues und Aufgaben, die Coding-Agents sehen und abarbeiten können. Deshalb hat die App zwei Bereiche:

- **To-Dos** – persönliche Aufgaben, z. B. Übungsblätter, Abgaben, Termine
- **Dev** – GitHub-Arbeit: Pull Requests, Reviews und Dev-To-dos (später auch dringende Issues und Agent-Issues)

SwiftUI, keine externen Abhängigkeiten, ab macOS 14. Die Oberfläche ist an Apples Dynamic Island angelehnt: tiefschwarzes Panel, Pillen und Kapseln, leuchtende Farbakzente und kurze, federnde Animationen.

## To-Dos

- **Anlegen:** Feld „Was steht an?“ → Titel, Priorität (Hoch, Mittel, Niedrig oder eigene Prioritäten mit Stufe 1–5), Gruppe, Ablaufdatum, Extra-Erinnerung und Wiederholung (täglich, wöchentlich, monatlich, eigene Wochentage).
- **Karten:** Die Prioritätsfarbe läuft als Verlauf von links ins Schwarze, der Rand schimmert. Darunter zeigen kleine Pillen Datum (rot, wenn überfällig), Erinnerung, Wiederholung und Gruppe.
- **Schnell bearbeiten:** Doppelklick auf den Titel benennt um. Der runde ⋯-Button ändert Priorität und Gruppe, öffnet Fälligkeit und Wiederholung, archiviert oder löscht.
- **Gruppen:** Pillen-Kopf mit Farbe und Anzahl, darunter eine Notizzeile, die beim Tippen mitwächst. Gruppen lassen sich am Griff ≡ verschieben, To-Dos per Drag-and-drop in Gruppen, zwischen Gruppen und wieder heraus ziehen.
- **Sortierung:** automatisch (offen vor erledigt, dann Priorität, Fälligkeit, Erstellung) oder manuell per Drag-and-drop.
- **Kopfzeile:** Die Status-Pille zeigt offene und überfällige To-Dos sowie wartende Reviews. Daneben: 🔍 Suche mit Filter-Voreinstellungen (Überfällig, Heute, Priorität, Gruppe …), 🗄 Archiv, 📅 Fälligkeitsansicht (Überfällig, Heute, Morgen, Diese Woche, Später), ⚙️ Einstellungen.
- **Archiv:** Erledigte, nicht wiederkehrende To-Dos landen im Archiv und lassen sich wiederherstellen oder endgültig löschen.
- **Rückgängig (⌘Z):** für Löschen, Erledigen, Verschieben, Archivieren und Gruppenänderungen.
- **Erinnerungen:** lokale macOS-Mitteilungen. Vorlaufzeit je Priorität einstellbar, niedrige Priorität einmal täglich zur gewählten Uhrzeit.

## Dev-Bereich

Der Dev-Bereich spricht GitHub **ausschließlich über die GitHub CLI (`gh`)** an. Die App selbst speichert keine Tokens, Passwörter oder Kontodaten – die Anmeldung liegt allein bei `gh`.

### Einrichtung

```bash
brew install gh
gh auth login
```

Danach den Dev-Bereich öffnen. Die App findet `gh` unter `/opt/homebrew/bin`, `/usr/local/bin` oder `/usr/bin`. Fehlt die CLI oder ist sie nicht angemeldet, zeigt der Dev-Bereich genau diese Befehle zum Kopieren an.

**Repositories auswählen:** Einstellungen → Allgemein → GitHub. Standardmäßig sind alle eigenen Repositories aktiv. Die Pille „N Repos ▸“ im Dev-Bereich führt direkt dorthin.

### Pull Requests

- **Zähler-Pillen** oben: 👀 Review angefordert, ✕ CI rot, ↗ meine PRs. Ein Klick springt zum passenden Abschnitt.
- **Abschnitte:** „Review von mir angefordert“, „Meine PRs“, „Sonstige“.
- **PR-Karte:** CI-Punkt (grün = bestanden, rot = fehlgeschlagen, gelb pulsierend = läuft, grau = keine CI), Titel, `repo #Nr`, Autor, Alter, Draft-Kennzeichen. Klick auf die Karte öffnet den PR im Browser.
- **Mergen:** nur bei grüner oder fehlender CI und nicht bei Drafts. Erster Klick → „Wirklich mergen?“, zweiter Klick → Merge-Commit (`gh pr merge --merge`). Danach verschwindet die Karte und ein Hinweis bestätigt den Merge.
- **Aktualisierung:** beim Öffnen des Dev-Bereichs, alle 2 Minuten, solange das Panel offen ist, und per ↻.

### Dev-To-dos

Eigene Liste nur im Dev-Bereich – für Entwicklungs- und Agent-Aufgaben, getrennt von den normalen To-Dos (sie erscheinen nicht in Liste, Zähler oder Archiv).

- Über das Eingabefeld anlegen, abhaken, Titel direkt bearbeiten, Priorität ändern, löschen.
- **„Als To-do“** auf einer PR-Karte legt „Review: <PR-Titel> (repo #Nr)“ an – Priorität Hoch, wenn das Review von mir angefordert ist, sonst Mittel. Der PR-Link hängt als klickbare Pille daran.

## Bauen und starten

Voraussetzungen: macOS 14 oder neuer, Xcode oder Swift 6 mit macOS-SDK.

```bash
zsh check.command          # Regressionstests
pkill -x ToDoList          # laufende Instanz beenden
zsh build.command --open   # bauen und starten
```

Die App entsteht unter `dist/todo list.app`. Sie ist lokal ad-hoc signiert und nicht für die öffentliche Verteilung notarisiert.

## Daten und Datenschutz

Alle Daten liegen lokal unter:

```text
~/Library/Application Support/todo list/
├── todos.json
├── groups.json
├── custom-priorities.json
└── Backups/
```

- Gespeichert wird atomar. Ist eine Datei beschädigt, überschreibt die App sie nicht.
- **Export/Import** (Einstellungen → Allgemein → Daten sichern) als JSON. Vor jedem Import wird der bisherige Stand in `Backups/` gesichert. Exporte enthalten alles im Klartext.
- Darstellung, Repo-Auswahl und der letzte GitHub-Stand liegen in den macOS-Benutzereinstellungen.
- Keine Tokens oder Zugangsdaten im Projekt oder in der App. Lokale Daten, Build-Ausgaben und Editor-Einstellungen werden von Git ignoriert.

## Projektstruktur

| Pfad | Inhalt |
| --- | --- |
| `Sources/KleineListe/App.swift` | Panel, To-Do-Liste, Einstellungen, Editor |
| `Sources/KleineListe/Store.swift` | Datenmodell, Filter, Speicherung, Rückgängig, Export/Import |
| `Sources/KleineListe/Dev.swift` | Dev-Bereich: PRs, Merge, Dev-To-dos |
| `Sources/KleineListe/GitHub.swift` | Aufruf der GitHub CLI, PR-Parsing, CI-Status |
| `Sources/KleineListe/Island.swift` | Gemeinsamer Island-Look (Pillen, Karten, Schalter, Animation) |
| `Sources/KleineListe/Notifications.swift` | Mitteilungen und Erinnerungen |
| `Sources/KleineListe/ClockIcon.swift` | Uhr-Icon für Menüleiste und App |
| `Resources/AppIcon.icns`, `Scripts/` | Farbiges App-Icon und Skript zum Erzeugen der PNGs |
| `Checks/StoreCheck.swift` | Regressionstests (ohne Netzwerk) |
| `build.command` / `check.command` | Build und Tests |
| `AGENTS.md` | Regeln für Coding-Agents in diesem Repository |

### Icons

Die Menüleiste zeigt eine eigene Uhr mit Gesicht: lächelnd, wenn alles erledigt ist, sonst neutral. Das Template-Bild passt sich dem hellen und dunklen macOS-Modus an. `Resources/AppIcon.icns` enthält das passende farbige Finder-Icon. Die gemeinsame Vektorgrafik liegt in `Sources/KleineListe/ClockIcon.swift`. Nach Änderungen erzeugt `zsh check.command` die PNG-Auflösungen neu; das App-Icon lässt sich anschließend mit `iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns` aktualisieren.

## Arbeitsweise

- Jede Änderung hat ein GitHub-Issue mit Titel im Format `[P<Priorität>-<laufende Nr>] Titel`.
- Gearbeitet wird auf eigenen Branches (`feature/<issue>-…`, `fix/<issue>-…`). Commits verweisen auf das Issue (`Refs #N` / `Closes #N`), gemergt wird über Pull Requests.
- Nach jeder Aufgabe: `check.command` ausführen, App neu bauen und starten (siehe `AGENTS.md`).

## Roadmap

- Dringende Issues im Dev-Bereich (#26)
- Agent-Issues: Aufgaben, die Coding-Agents sehen und abarbeiten können (#27)
- Insel an der Notch als Alternative zum Menüleisten-Panel (#50)
