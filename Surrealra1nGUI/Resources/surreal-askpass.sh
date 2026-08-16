#!/bin/sh
/usr/bin/osascript <<'APPLESCRIPT'
tell application "System Events"
    activate
    display dialog "surrealra1n needs administrator access to communicate with the device and mount restore images." default answer "" with hidden answer buttons {"Cancel", "Continue"} default button "Continue" with title "surrealra1n"
    text returned of result
end tell
APPLESCRIPT
