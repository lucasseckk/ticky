#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/checks
swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/Ticky/Store.swift Sources/Ticky/GitHub.swift Sources/Ticky/ReminderPlan.swift Checks/StoreCheck.swift -o .build/checks/StoreCheck
.build/checks/StoreCheck
swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/Ticky/ClockIcon.swift Scripts/main.swift -o .build/checks/ClockIconCheck
.build/checks/ClockIconCheck .build/AppIcon.iconset
rm -rf .build/checks/strings && mkdir -p .build/checks/strings
swiftc -module-cache-path "$PWD/.build/ModuleCache" -parse-as-library -module-name Ticky -wmo -c -o /dev/null \
    -emit-localized-strings -emit-localized-strings-path .build/checks/strings Sources/Ticky/*.swift
swiftc -module-cache-path "$PWD/.build/ModuleCache" -parse-as-library Checks/StringsCheck.swift -o .build/checks/StringsCheck
.build/checks/StringsCheck .build/checks/strings Resources/Localizable.en.json
