# Agent instructions

For every request in this repository, all agents must use the Ponytail skill in addition to their normal workflow. This applies to agents launched through both Superpowers and oh-my-codex.

Use Ponytail at its `full` level by default: prefer the smallest complete change, avoid unnecessary abstractions, and verify the result before reporting completion. Higher-priority system or user instructions take precedence.

## App nach jedem Prompt starten

Sobald ein Prompt vollständig abgearbeitet ist, muss die App neu gebaut und gestartet werden, damit das Ergebnis direkt getestet werden kann:

```bash
zsh check.command
zsh build.command --open
```

Läuft bereits eine ältere Instanz, wird sie vorher beendet (`pkill -x ToDoList`). Schlägt der Check, der Build oder der Start fehl, wird das im Abschluss klar gemeldet, statt die Aufgabe als fertig zu melden.
