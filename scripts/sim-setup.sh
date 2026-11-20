#!/bin/bash
# The state every simulator is put in before it is looked at.
#
# Dark, because that is how the owner reads the archive, and because a screen that is checked in
# light and used in dark is checked in the wrong place. Standard text size, because a run that
# enlarged it for an accessibility check leaves it enlarged for the next one, and the next
# screenshot then looks broken for a reason that has nothing to do with the change being made.
#
# The wallpaper is NOT one of these settings, and cannot be: the Simulator offers no way to change
# it. `simctl ui` has appearance, contrast and text size and nothing else; the Settings app inside
# the simulator has no Wallpaper section on either iOS 17.5 or 26.5; and the old trick of dropping
# a black image into data/Library/SpringBoard is ignored — iOS 17 draws the home screen through
# PosterBoard, and SpringBoard was restarted with the same bright wallpaper. Anything further means
# editing PosterBoard's own undocumented store, which would break at the next runtime update.
# The wallpaper is only ever behind the home screen; nothing of the app is drawn over it.
#
#   scripts/sim-setup.sh                       the routine three, dark and standard
#   scripts/sim-setup.sh --appearance light    for a check in light
#   scripts/sim-setup.sh --size accessibility-extra-large
#   scripts/sim-setup.sh --device iPhoneiOS17  the floor, for a full check
#   scripts/sim-setup.sh --device booted       whatever happens to be running
#
# The routine three run on the newest installed iOS and are the stock simulators, so they are not
# created here — Xcode already ships them. The floor devices `iPhoneiOS17` and `iPadiOS17` (iOS
# 17.5) are created if they do not exist, so deleting simulators to reclaim disk costs nothing but
# the download they already have. They are asked for by name rather than run every time: iOS 17 is
# the supported floor, checked before a build goes out and after a large feature lands, and both the
# phone and the tablet are covered then.
set -euo pipefail

appearance=dark
size=medium
devices=('iPhone 17 Pro Max' 'iPhone SE (3rd generation)' 'iPad Pro 11-inch (M5)')
explicit_devices=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --appearance) appearance="$2"; shift 2 ;;
        --size) size="$2"; shift 2 ;;
        --device) explicit_devices+=("$2"); shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ ${#explicit_devices[@]} -gt 0 ]]; then
    devices=("${explicit_devices[@]}")
fi

# The floor devices, made if they are not there. They are named rather than described because the
# test script asks for them by name, and a simulator is a throwaway thing — deleting one to reclaim
# the disk should not cost anybody the knowledge of how it was built.
floor_runtime=com.apple.CoreSimulator.SimRuntime.iOS-17-5

floor_type() {
    case "$1" in
        iPhoneiOS17) echo com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation ;;
        iPadiOS17) echo com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M4-8GB ;;
        *) echo "" ;;
    esac
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for device in "${devices[@]}"; do
    type_id=$(floor_type "$device")
    if [[ -n $type_id ]] && ! xcrun simctl list devices available | grep -q "^    $device ("; then
        echo "creating $device on iOS 17.5"
        xcrun simctl create "$device" "$type_id" "$floor_runtime" >/dev/null
    fi
    # By UDID, not by name: the routine phones are installed on two runtimes each, and `simctl`
    # refuses an ambiguous name. `booted` is simctl's own word and stays as written.
    if [[ $device == booted ]]; then
        target=booted
    else
        target=$("$script_dir/sim-udid.sh" "$device")
    fi
    if ! xcrun simctl bootstatus "$target" -b >/dev/null 2>&1; then
        xcrun simctl boot "$target" >/dev/null 2>&1 || true
        xcrun simctl bootstatus "$target" -b >/dev/null 2>&1 || true
    fi
    xcrun simctl ui "$target" appearance "$appearance" >/dev/null
    xcrun simctl ui "$target" content_size "$size" >/dev/null
    echo "$device: appearance=$appearance content_size=$size"
done
