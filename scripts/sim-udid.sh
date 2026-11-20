#!/bin/bash
# Prints the UDID of an available simulator, given its name.
#
# It exists because a name no longer identifies a simulator. `iPhone SE (3rd generation)` is
# installed on both iOS 17.5 and iOS 26.5, and the obvious lookup — take the first match — returned
# the 17.5 one, because that is the order `simctl` lists runtimes in. The routine tests therefore
# claimed the newest OS and quietly ran on the floor. When a name matches more than one simulator,
# the newest runtime wins; ask for the floor by its own name (`iPadiOS17`) instead.
#
#   scripts/sim-udid.sh 'iPhone SE (3rd generation)'
#   scripts/sim-udid.sh iPadiOS17
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: sim-udid.sh <simulator name>" >&2
    exit 2
fi

udid=$(xcrun simctl list devices available --json | SIM_NAME="$1" python3 -c '
import json, os, re, sys

name = os.environ["SIM_NAME"]
devices = json.load(sys.stdin)["devices"]


def version(runtime):
    return [int(part) for part in re.findall(r"\d+", runtime.rsplit(".", 1)[-1])]


matches = [
    (version(runtime), device["udid"])
    for runtime, entries in devices.items()
    for device in entries
    if device["name"] == name
]
if matches:
    print(max(matches)[1])
')

if [[ -z $udid ]]; then
    echo "No available simulator named '$1'." >&2
    exit 1
fi

echo "$udid"
