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

## Agent-Aufgaben

Aufgaben für Coding-Agents sind GitHub-Issues mit dem Label `agent`. Die App zeigt sie im Dev-Bereich unter „Agent-Aufgaben“ mit ihrem Status an.

```bash
gh issue list --label agent --state open             # offene Aufgaben finden
gh issue view <Nr> --comments                        # Aufgabe und Akzeptanzkriterien lesen
gh issue edit <Nr> --add-label agent:in-arbeit       # Status in der App: „In Arbeit“
```

- Nur Issues mit dem Label `agent` selbstständig übernehmen, und immer nur eines gleichzeitig.
- Auf einem neuen Branch arbeiten. Der Pull Request enthält „Closes #<Nr>“ – damit zeigt die App „PR offen“ und nach dem Merge „Erledigt“.
- Ist die Aufgabe unklar oder nicht umsetzbar, Label `agent:in-arbeit` wieder entfernen und die offene Frage als Kommentar ins Issue schreiben, statt zu raten.
- Keine Pull Requests selbst mergen; das entscheidet der Nutzer in der App.
