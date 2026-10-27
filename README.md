# To-Do List

Native macOS-Menüleisten-App für To-dos. Die App verwendet SwiftUI, benötigt keine externen Abhängigkeiten und läuft ab macOS 14.

## Funktionen

- To-dos mit Priorität, Fälligkeit, Wiederholungen und optionalen Erinnerungen
- Lokale macOS-Benachrichtigungen
- Gruppen mit Notizen und individuellen Farben
- Suche und kombinierbare Filter für Status, Gruppe, Priorität und Fälligkeit
- Fälligkeitsansicht: Überfällig, Heute, Morgen, Diese Woche, Später
- Automatische oder manuelle Reihenfolge per Drag-and-drop
- Schnellbearbeitung auf der Karte (Doppelklick auf den Titel, Priorität und Gruppe im ⋯-Menü)
- Rückgängig (⌘Z) für Löschen, Verschieben, Erledigen und Gruppenänderungen
- Archiv für erledigte To-dos
- Export und Import als JSON-Sicherung
- Drag-and-drop in Gruppen, zwischen Gruppen und zurück in den normalen Bereich
- Transparente Drag-Vorschau
- Animierte Erstellung und Darstellung
- Einstellungen für Darstellung, Gruppen und Benachrichtigungen
- Atomare lokale Speicherung ohne Netzwerkverbindung

## Bauen und starten

Voraussetzungen:

- macOS 14 oder neuer
- Xcode oder Swift 6 mit funktionierendem macOS-SDK

Im Projektordner ausführen:

```bash
zsh check.command
zsh build.command --open
```

Die fertige App wird unter `dist/todo list.app` erzeugt. Der Build ist lokal ad-hoc signiert und nicht für die öffentliche Verteilung notarisiert.

## Daten und Datenschutz

Die App speichert To-dos lokal unter:

```text
~/Library/Application Support/todo list/
```

Vor jedem Import wird der bisherige Stand unter `Backups/` in diesem Ordner gesichert. Exporte enthalten alle To-dos im Klartext und sollten entsprechend aufbewahrt werden.

Es werden keine Zugangsdaten, API-Schlüssel oder Kontoinformationen im Projekt benötigt. Benachrichtigungen verwenden ausschließlich die lokale macOS-API. Lokale Daten, Build-Ausgaben, Editor-Einstellungen und Agent-Metadaten gehören nicht in ein öffentliches Repository und werden deshalb ignoriert.

## Projektstruktur

- `Sources/KleineListe/` – App, Datenmodell und Benachrichtigungen
- `Checks/` – kleiner persistenzbezogener Regressionstest
- `build.command` – lokaler Release-Build
- `check.command` – Regressionstest

### Icons

Die Menüleiste zeigt eine eigene Uhr mit Gesicht: lächelnd, wenn alles erledigt ist,
sonst neutral. Das Template-Bild passt sich dem hellen und dunklen macOS-Modus an.
`Resources/AppIcon.icns` enthält das passende farbige Finder-Icon.
Die gemeinsame Vektorgrafik liegt in `Sources/KleineListe/ClockIcon.swift`.
Nach Änderungen erzeugt `zsh check.command` die PNG-Auflösungen neu; das App-Icon
lässt sich anschließend mit `iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns` aktualisieren.
