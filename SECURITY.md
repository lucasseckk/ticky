# Sicherheitsrichtlinie

*English: please report vulnerabilities privately via GitHub (Security → Report a vulnerability), never in a public issue.*

## Unterstützte Versionen

| Version | Sicherheitsupdates |
| --- | --- |
| neuestes Release (aktuell 1.0.x) | ✅ |
| ältere Versionen | ❌ – bitte auf das neueste Release aktualisieren |

Fixes erscheinen als neues Release unter [Releases](https://github.com/lucasseckk/ticky/releases).

## Sicherheitslücke melden

**Bitte kein öffentliches Issue, keinen Pull Request und keine Diskussion zu einer Sicherheitslücke anlegen.**

Melde sie vertraulich über GitHub:
[Security → Report a vulnerability](https://github.com/lucasseckk/ticky/security/advisories/new).
Die Meldung sehen nur die Maintainer.

Hilfreich sind:

- betroffene Version (Einstellungen → Allgemein, unten) und macOS-Version,
- was passiert und was ein Angreifer damit erreichen kann,
- Schritte zum Nachstellen.

Schick keine echten Zugangsdaten, Tokens oder persönlichen Daten mit, auch nicht deine eigenen. Für die Meldung reichen ausgedachte Beispieldaten.

## Was danach passiert

- **Eingangsbestätigung** innerhalb von 7 Tagen.
- **Einschätzung**, ob und wie schwer die Lücke ist, innerhalb von 14 Tagen.
- **Fix** so schnell wie möglich, als neues Release. Du wirst über den Stand informiert und auf Wunsch im Advisory genannt.

Bitte veröffentliche Details erst, wenn ein Fix erschienen ist oder wir das gemeinsam vereinbart haben.

## Was in den Bereich fällt

- die App Ticky und ihre Daten unter `~/Library/Application Support/Ticky/`,
- der Dev-Bereich und die Anbindung an die GitHub CLI (`gh`),
- Installer, Buildskripte und GitHub-Workflows in diesem Repository.

Die Sicherheitsgrenzen der App (Dateirechte, FileVault statt eigener Verschlüsselung) stehen in der [README unter „Daten und Datenschutz“](README.md#daten-und-datenschutz).
