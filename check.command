#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/checks
swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/KleineListe/Store.swift Sources/KleineListe/GitHub.swift Checks/StoreCheck.swift -o .build/checks/StoreCheck
.build/checks/StoreCheck
swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/KleineListe/ClockIcon.swift Scripts/main.swift -o .build/checks/ClockIconCheck
.build/checks/ClockIconCheck .build/AppIcon.iconset
