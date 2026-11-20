#!/bin/zsh

# Runs the UI tests against the in-memory sample archive, never the reader's own.
#
# These went red and stayed red because nothing ran them: the routine script covers the unit tests
# only, and the UI scheme was left to be remembered. Give it a script of its own and it can be run
# as easily as the other one.
#
# Usage: scripts/test-ios-ui.sh [device name] [-- extra xcodebuild args]
#   scripts/test-ios-ui.sh
#   scripts/test-ios-ui.sh 'iPhone 17 Pro Max'
#   scripts/test-ios-ui.sh 'iPad Pro 11-inch (M5)'
#   scripts/test-ios-ui.sh 'iPhone SE (3rd generation)' -- -only-testing:ArchiveLeafUITests/LocalizationUITests
#
# The routine three run on the newest installed iOS: the two phones as the extremes of the compact
# width, the iPad for regular width. A name installed on two runtimes resolves to the newer one
# (`scripts/sim-udid.sh`), so these read as written.
#
# Run the floor before a build goes out and after a large feature lands — both devices, not one.
# iOS 17 is the supported floor, the owner's iPad cannot go past it, and the two versions behave
# differently: a back button carries an identifier on 26 and none on 17, so tests written against
# one did not run on the other at all.
#   scripts/test-ios-ui.sh iPhoneiOS17
#   scripts/test-ios-ui.sh iPadiOS17
#
# Between those points the floor is not simulated at all, because the owner's own iPad is on 17 and
# is used daily. That is also why the devices are paired the way they are: newest OS on the smallest
# phone, floor OS on the tablet.
#
# While iterating, run ONE class on ONE device — about a minute, against five for the suite on two.
# The whole suite is for before a commit or a build going out, not for every small fix.
#
#   scripts/test-ios-ui.sh iPadiOS17 -- -only-testing:ArchiveLeafUITests/BrowsingNavigationUITests
#
# Which class covers what:
#   BrowsingNavigationUITests  folders, tabs, going in and coming back up
#   TrashSwipeUITests          the Trash: restoring and deleting
#   BrowserFailureUITests      a document's links and the archive's own browser
#   LocalizationUITests        the interface translated, archive names left alone

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
# The device may be left out and the extra arguments given on their own, which reads as
# `scripts/test-ios-ui.sh -- -only-testing:…`. Without this the `--` was taken for a device name.
if [[ ${1:-} == "--" ]]; then
    device='iPhone SE (3rd generation)'
else
    device=${1:-iPhone SE (3rd generation)}
    shift 2>/dev/null || true
fi
if [[ ${1:-} == "--" ]]; then
    shift
fi

cd $project_root

# Dark, always. Appearance is part of what these tests look at, and a simulator left in light mode
# is a different set of pixels than the one anybody checks by hand.
udid=$($script_dir/sim-udid.sh $device) || exit 2
xcrun simctl boot $udid 2>/dev/null || true
xcrun simctl bootstatus $udid -b >/dev/null 2>&1 || true
# The same baseline `scripts/sim-setup.sh` writes, so a run never inherits the text size a
# previous accessibility check left behind.
xcrun simctl ui $udid appearance dark >/dev/null 2>&1 || true
xcrun simctl ui $udid content_size medium >/dev/null 2>&1 || true

xcodebuild test \
    -project ArchiveLeaf.xcodeproj \
    -scheme ArchiveLeafUITests \
    -destination "platform=iOS Simulator,id=$udid" \
    "$@"
