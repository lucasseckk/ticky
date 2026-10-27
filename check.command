#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/checks
swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/KleineListe/Store.swift Checks/StoreCheck.swift -o .build/checks/StoreCheck
.build/checks/StoreCheck
