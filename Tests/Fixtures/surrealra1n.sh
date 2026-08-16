#!/bin/bash

set -u
IDENTIFIER="iPhone12,3"
ECID="1234"

pick_file() {
    echo "$2"
}

# Dependency check
echo "Checking for updates..."
echo "Checking for existing binaries..."

just_boot(){
read -p "Input the version you'd like to boot: " VERSION
bootdir="boot/$IDENTIFIER/$VERSION"
echo "Sending iBSS"
echo "Sending iBEC"
echo "Sending DeviceTree"
echo "Sending trustcache"
echo "Sending Kernelcache"
echo "Device should now boot"
}

main_menu() {
    echo "1. Downgrade Options"
    echo "2. Misc Utilities"
    echo "3. Switch to main branch"
    echo "4. Exit"
    read -p "Please input an option (1-4): " choice
    [[ "$choice" == "1" ]] || exit 40
}

restore_menu() {
    echo "1. Restore (with SHSH blobs)"
    echo "2. Restore (Tethered)"
    echo "3. Restore to 10.3.3 untethered (some A7 devices only)"
    echo "4. Just Boot"
    echo "5. Back"
    read -p "Please input an option (1-5): " choice
    case "$choice" in
        1) blob_menu ;;
        2) tethered_menu ;;
        3) untethered_menu ;;
        4) just_boot ;;
        *) exit 41 ;;
    esac
}

tethered_menu() {
    local choice
    local target=""
    local base=""
    while true; do
        echo "1. Select Target IPSW"
        echo "2. Select Base IPSW"
        echo "3. Start Restore"
        echo "4. Back"
        read -p "Please input an option (1-4): " choice
        case "$choice" in
            1) target=$(pick_file "Select an IPSW file") ;;
            2) base=$(pick_file "Select iOS 26 IPSW file") ;;
            3)
                [[ -n "$target" && -n "$base" ]] || exit 42
                echo "Archive: $target"
                echo "Patching firmware"
                echo "Adding: custom.ipsw"
                echo "Restoring 25%"
                echo "Restoring 100%"
                echo "Restore has completed! Read above if there are any errors"
                if [[ "${SURREAL_TEST_HELD_PIPE:-}" == "1" ]]; then
                    sleep 3 &
                fi
                return
                ;;
        esac
    done
}

blob_menu() {
    local choice
    local target=""
    local blob=""
    while true; do
        echo "1. Select Target IPSW"
        echo "2. Select SHSH"
        echo "3. Start Restore"
        echo "4. Back"
        read -p "Please input an option (1-4): " choice
        case "$choice" in
            1) target=$(pick_file "Select an IPSW file") ;;
            2) blob=$(pick_file "Select an SHSH2 file") ;;
            3)
                [[ -n "$target" && -n "$blob" ]] || exit 43
                echo "Restore has finished"
                return
                ;;
        esac
    done
}

untethered_menu() {
    local choice
    local target=""
    while true; do
        echo "1. Select 10.3.3 IPSW"
        echo "2. Start Restore"
        echo "3. Back"
        read -p "Please input an option (1-3): " choice
        case "$choice" in
            1) target=$(pick_file "Select an IPSW file") ;;
            2)
                [[ -n "$target" ]] || exit 44
                echo "Restore has finished"
                return
                ;;
        esac
    done
}

main_menu
echo "A12/A13 device support is entirely experimental."
echo "Expect to have issues or bugs."
read -p "Press enter to continue"
if [[ "${SURREAL_TEST_EARLY_EXIT:-}" == "1" ]]; then
    restore_menu &
    exit 0
fi
restore_menu
if [[ "${SURREAL_TEST_SUCCESS_EXIT:-}" == "1" ]]; then
    exit 7
fi
