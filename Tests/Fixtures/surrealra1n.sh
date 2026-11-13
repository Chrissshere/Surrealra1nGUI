#!/bin/bash

set -u
IDENTIFIER="${SURREAL_TEST_DEVICE_IDENTIFIER:-iPhone12,3}"
ECID="1234"

if [[ "${SURREAL_TEST_PACKAGE_MANAGER_PROMPT:-}" == "1" ]]; then
    echo "Using Homebrew"
    read -r -p "Use MacPorts instead? [y/n] " response
    case "$response" in
        y) printf '\nPackage manager choice: MacPorts\n' ;;
        n) printf '\nPackage manager choice: Homebrew\n' ;;
        *) exit 45 ;;
    esac
fi

pick_file() {
    echo "$2"
}

# Dependency check
echo "Checking for updates..."
echo "Checking for existing binaries..."

just_boot(){
read -p "Input the version you'd like to boot: " VERSION
bootdir="boot/$IDENTIFIER/$VERSION"
if [[ "${SURREAL_TEST_BOOT_FILES:-}" == "1" ]]; then
    [[ -f "$bootdir/iBSS.img4" ]] || exit 46
fi
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
    if [[ "${SURREAL_TEST_LEGACY_MENU:-}" == "1" ]]; then
        echo "3. Switch to main branch"
        echo "4. Exit"
        read -p "Please input an option (1-4): " choice
    else
        echo "3. Additional Tools"
        echo "4. Switch to main branch"
        echo "5. Exit"
        read -p "Please input an option (1-5): " choice
        if [[ "$choice" == "5" ]]; then exit 0; fi
    fi
    [[ "$choice" == "1" ]] || exit 40
}

restore_menu() {
    echo "1. Restore (with SHSH blobs)"
    echo "2. Restore (Tethered)"
    echo "3. Restore to 10.3.3 untethered (some A7 devices only)"
    echo "4. Just Boot"
    if [[ "$IDENTIFIER" == "iPad5,1" || "$IDENTIFIER" == "iPod7,1" ]]; then
        echo "5. Additional Install Option"
        echo "6. Back"
        read -p "Please input an option (1-6): " choice
    else
        echo "5. Back"
        read -p "Please input an option (1-5): " choice
    fi
    case "$choice" in
        1) blob_menu ;;
        2) tethered_menu ;;
        3) untethered_menu ;;
        4) just_boot ;;
        *) exit 41 ;;
    esac
}

select_ipsw() {
    local role="$1"
    local choice
    if [[ "${SURREAL_TEST_LEGACY_MENU:-}" != "1" ]]; then
        echo "Please select a method to obtain the $role ipsw."
        echo "1. Select an IPSW file"
        echo "2. Download an IPSW file Online"
        echo "3. Exit"
        read -p "Please input an option (1-3): " choice
        [[ "$choice" == "1" ]] || exit 47
    fi
    if [[ "$role" == "base" ]]; then
        selected_ipsw=$(pick_file "Select iOS 26 IPSW file")
    else
        selected_ipsw=$(pick_file "Select an IPSW file")
    fi
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
            1) select_ipsw target; target="$selected_ipsw" ;;
            2) select_ipsw base; base="$selected_ipsw" ;;
            3)
                [[ -n "$target" && -n "$base" ]] || exit 42
                echo "Archive: $target"
                echo "Patching firmware"
                echo "Adding: custom.ipsw"
                echo "Restoring 25%"
                echo "Restoring 100%"
                printf 'Restore has '
                sleep 0.04
                echo "completed! Read above if there are any errors"
                if [[ "${SURREAL_TEST_BOOT_FILES:-}" == "1" && ! -f ".fixture-restore-ran" ]]; then
                    echo "Waiting to finish writing simulated boot files"
                    for ((attempt = 0; attempt < 250; attempt++)); do
                        [[ -f ".finish-fixture" ]] && break
                        sleep 0.02
                    done
                    [[ -f ".finish-fixture" ]] || exit 48
                    mkdir -p "boot/$IDENTIFIER/16.4"
                    printf 'simulated boot file\n' > "boot/$IDENTIFIER/16.4/iBSS.img4"
                    echo "Simulated boot files are ready"
                    touch ".fixture-restore-ran"
                fi
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
            1) select_ipsw target; target="$selected_ipsw" ;;
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
            1) select_ipsw target; target="$selected_ipsw" ;;
            2)
                [[ -n "$target" ]] || exit 44
                echo "Restore has finished"
                return
                ;;
        esac
    done
}

main_menu
if [[ "${SURREAL_TEST_NO_DEVICE:-}" == "1" ]]; then
    echo "No connected device was found"
    main_menu
    exit 0
fi
echo "A12/A13 device support is entirely experimental."
echo "Expect to have issues or bugs."
read -p "Press enter to continue"
if [[ "${SURREAL_TEST_EARLY_EXIT:-}" == "1" ]]; then
    restore_menu &
    exit 0
fi
restore_menu
if [[ "${SURREAL_TEST_FAIL_AFTER_COMPLETION:-}" == "1" || -f ".fail-fixture" ]]; then
    exit 7
fi
