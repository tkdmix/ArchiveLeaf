#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
build_root=$(mktemp -d /private/tmp/ArchiveLeaf-memory-tests.XXXXXX)
result_bundle=$build_root/ArchiveLeaf-memory-tests.xcresult

cleanup() {
    rm -rf -- $build_root
}
trap cleanup EXIT

cd $project_root

# Build first so the generated xctestrun remains the source of truth for Xcode's current format.
xcodebuild -quiet build-for-testing \
    -project ArchiveLeaf.xcodeproj \
    -scheme ArchiveLeaf \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath $build_root

xctestruns=($build_root/Build/Products/*.xctestrun(N))
if (( ${#xctestruns} != 1 )); then
    print -u2 "Expected one xctestrun file, found ${#xctestruns}."
    exit 1
fi

# Keep the copy beside the built products. __TESTROOT__ is resolved from this location, so moving
# it to /private/tmp itself would make Xcode look for the test host under /private/tmp/Debug.
memory_xctestrun=$build_root/Build/Products/ArchiveLeaf-memory-tests.xctestrun
cp $xctestruns[1] $memory_xctestrun

environment_value=$(/usr/libexec/PlistBuddy \
    -c "Print :TestConfigurations:0:TestTargets:0:EnvironmentVariables:ARCHIVELEAF_DATA_SOURCE" \
    $memory_xctestrun 2>/dev/null || true)
if [[ $environment_value != memory ]]; then
    print -u2 "Expected the host xctestrun environment to set ARCHIVELEAF_DATA_SOURCE=memory; found ${environment_value:-missing}."
    exit 1
fi

xcodebuild -quiet test-without-building \
    -xctestrun $memory_xctestrun \
    -destination 'platform=macOS,arch=arm64' \
    -parallel-testing-enabled NO \
    -resultBundlePath $result_bundle

xcrun xcresulttool get test-results summary --path $result_bundle
