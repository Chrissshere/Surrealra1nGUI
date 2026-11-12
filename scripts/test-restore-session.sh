#!/bin/bash

set -e
cd "$(dirname "$0")/.."
testbin="${TMPDIR:-/tmp}/surrealra1n-restore-session-test"
xcrun swiftc -o "$testbin" \
    Surrealra1nGUI/{DeviceObserver,DFUInstructions,EngineWorkspace,InterfaceTheme,RestoreAssistant,RestoreLog,RestoreSession}.swift \
    Tests/RestoreAssistantLayout.swift Tests/RestoreSessionIntegration.swift
"$testbin" "$@"
rm -f "$testbin"
