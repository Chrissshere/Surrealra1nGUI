#!/bin/bash

set -e
cd "$(dirname "$0")/.."
testbin="${TMPDIR:-/tmp}/surrealra1n-restore-session-test"
xcrun swiftc -o "$testbin" Surrealra1nGUI/InterfaceTheme.swift Surrealra1nGUI/RestoreLog.swift Surrealra1nGUI/RestoreSession.swift Tests/RestoreSessionIntegration.swift
"$testbin" "$@"
rm -f "$testbin"
