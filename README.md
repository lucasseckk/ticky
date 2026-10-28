# To-Do List

Native macOS-Menüleisten-App für To-dos – gebaut für den Alltag zwischen **Uni und Entwicklung**.

Die App ist eine ganz normale To-do-Liste, wie man sie kennt: Aufgaben, Fälligkeiten, Erinnerungen, Gruppen. Das eigentliche Ziel geht aber darüber hinaus: Sie soll der eine Ort sein, an dem ich neben Uni-Aufgaben auch meine **Entwicklungsarbeit** im Blick habe – offene Pull Requests, Reviews, dringende Issues und Aufgaben, die Coding-Agents sehen und abarbeiten können. Deshalb hat die App zwei Bereiche:

- **To-Dos** – persönliche Aufgaben, z. B. Übungsblätter, Abgaben, Termine
- **Dev** – GitHub-Arbeit: Pull Requests, Reviews, Agent-Aufgaben und eigene Dev-To-dos (später auch dringende Issues)

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

- **Beispiele:** Ein Review von dir selbst lässt sich auf GitHub nicht anfordern. Damit der Review-Abschnitt trotzdem sichtbar ist, zeigt die App drei lokale Beispiel-Reviews (CI grün, rot, laufend) mit dem Etikett „Beispiel“; Mergen wirkt bei ihnen nur lokal. Abschaltbar unter Einstellungen → Allgemein → GitHub. Echte Demo-PRs im Repo: #61 (grün), #62 (rot), #63 (Draft).

### Agent-Aufgaben

Aufgaben für Coding-Agents (Claude Code, Codex …) sind **GitHub-Issues mit dem Label `agent`**. So kann ein Agent sie selbst finden und lesen – die lokale App-Datei sieht er nicht, GitHub schon.

- **Anlegen:** „Neue Aufgabe“ → Repository, Titel, Aufgabe, Akzeptanzkriterien. Die App legt daraus ein strukturiertes Issue mit Label `agent` an.
- **Status** (aus GitHub abgeleitet): Offen → In Arbeit (Label `agent:in-arbeit`) → PR offen (ein PR enthält „Closes #Nr“, klickbar) → Erledigt (Issue geschlossen, bleibt eine Woche sichtbar).
- **An einen Agent übergeben:**
  - automatisch: Der Agent sucht selbst mit `gh issue list --label agent` – das Vorgehen steht in `AGENTS.md`;
  - oder per **Prompt**-Button: kopiert einen fertigen Prompt (Issue, Beschreibung, Vorgehen), den du in Claude Code oder Codex einfügst.
- Klick auf die Karte öffnet das Issue; im ⋯-Menü: PR öffnen, „in Arbeit“ setzen/zurücknehmen, Label entfernen.

### Meine Dev-To-dos

Eigene, lokale Liste nur im Dev-Bereich – für Notizen und Aufgaben, die nicht an einen Agent gehen. Sie erscheinen nicht in der normalen Liste, im Zähler oder im Archiv.

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

### Sicherheitsgrenzen

- **Dateirechte:** Der Datenordner ist nur für deinen Benutzer zugänglich (`0700`), alle Dateien inklusive Backups und Exporte sind nur für dich lesbar (`0600`). Andere Benutzer auf demselben Mac sehen nichts.
- **Verschlüsselung:** Die App verschlüsselt nicht selbst, sondern verlässt sich auf **FileVault** (Einstellungen → Datenschutz & Sicherheit). Eine eigene Verschlüsselung mit Schlüssel im Schlüsselbund wurde geprüft und verworfen: Die App ist nur ad-hoc signiert, dadurch ändert sich ihre Signatur bei jedem Build und der Schlüsselbund würde den Zugriff immer wieder neu abfragen oder verweigern – das Risiko, die eigenen Daten auszusperren, wäre größer als der Gewinn. Gegen Programme, die unter deinem Benutzer laufen, hilft beides nicht.
- **Exporte** sind Klartext-JSON mit allen To-dos und Notizen – wie ein Passwort-freies Dokument behandeln (nicht in geteilte Ordner oder öffentliche Repos legen).
- **GitHub:** Die App speichert keine Tokens. Zugriff läuft über die `gh`-Anmeldung, die im macOS-Schlüsselbund liegt. In den Benutzereinstellungen landen nur Login-Name, Repo-Liste und Auswahl.

## Projektstruktur

| Pfad | Inhalt |
| --- | --- |
| `Sources/KleineListe/App.swift` | Panel, To-Do-Liste, Einstellungen, Editor |
| `Sources/KleineListe/Store.swift` | Datenmodell, Filter, Speicherung, Rückgängig, Export/Import |
| `Sources/KleineListe/Dev.swift` | Dev-Bereich: PRs, Merge, Agent-Aufgaben, Dev-To-dos |
| `Sources/KleineListe/GitHub.swift` | Aufruf der GitHub CLI, PR- und Issue-Parsing, CI-Status |
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
- Insel an der Notch als Alternative zum Menüleisten-Panel (#50)
