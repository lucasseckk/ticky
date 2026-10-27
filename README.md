# To-Do List

Native macOS-Menüleisten-App für To-dos. Die App verwendet SwiftUI, benötigt keine externen Abhängigkeiten und läuft ab macOS 14.

## Funktionen

- To-dos mit Priorität, Fälligkeit, Wiederholungen und optionalen Erinnerungen
- Lokale macOS-Benachrichtigungen
- Gruppen mit Notizen und individuellen Farben
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

Es werden keine Zugangsdaten, API-Schlüssel oder Kontoinformationen im Projekt benötigt. Benachrichtigungen verwenden ausschließlich die lokale macOS-API. Lokale Daten, Build-Ausgaben, Editor-Einstellungen und Agent-Metadaten gehören nicht in ein öffentliches Repository und werden deshalb ignoriert.

## Projektstruktur

- `Sources/KleineListe/` – App, Datenmodell und Benachrichtigungen
- `Checks/` – kleiner persistenzbezogener Regressionstest
- `build.command` – lokaler Release-Build
- `check.command` – Regressionstest
