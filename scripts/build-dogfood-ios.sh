#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
# ARCHIVELEAF_BUILD_ROOT overrides where builds are kept. The default sits beside the project, outside
# the working tree, and the .noindex suffix keeps the archives out of Spotlight.
build_root=${ARCHIVELEAF_BUILD_ROOT:-${project_root:h}/ArchiveLeaf-TestBuilds.noindex}
ios_root=$build_root/iOS
bundle_id=io.github.inadaman.ArchiveLeaf
device=''
should_launch=false
allow_dirty=false

usage() {
    print 'Usage: scripts/build-dogfood-ios.sh [--device <udid>] [--launch] [--allow-dirty]'
    print '  --device       Target device UDID. Defaults to the only paired device.'
    print '  --launch       Launch the installed build, replacing any running instance.'
    print '  --allow-dirty  Permit a build from an uncommitted working tree.'
    print 'Builds are kept in ARCHIVELEAF_BUILD_ROOT, by default ../ArchiveLeaf-TestBuilds.noindex.'
}

while (( $# > 0 )); do
    case $1 in
        --device)
            shift
            (( $# > 0 )) || { print -u2 '--device needs a UDID.'; exit 2 }
            device=$1
            ;;
        --launch)
            should_launch=true
            ;;
        --allow-dirty)
            allow_dirty=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown option: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

cd $project_root

if [[ $allow_dirty == false ]] && [[ -n $(git status --short) ]]; then
    print -u2 'Refusing to build Dogfood from an uncommitted working tree.'
    print -u2 'Commit the settled revision, or explicitly pass --allow-dirty.'
    exit 1
fi

if [[ -z $device ]]; then
    # Only auto-select when the choice is unambiguous; installing onto the wrong phone is not
    # something to guess at.
    devices=(${(f)"$(xcrun devicectl list devices 2>/dev/null | awk '/available/ { print $3 }')"})
    if (( ${#devices} == 0 )); then
        print -u2 'No paired device is available. Connect one, or pass --device <udid>.'
        exit 1
    fi
    if (( ${#devices} > 1 )); then
        print -u2 "More than one device is available; pass --device <udid>:"
        printf '  %s\n' $devices >&2
        exit 1
    fi
    device=$devices[1]
fi

timestamp=$(date '+%Y%m%d-%H%M%S')
revision=$(git rev-parse --short HEAD)
staging_root=$ios_root/.staging-$timestamp-$revision
derived_data=$staging_root/DerivedData
built_app=$derived_data/Build/Products/Release-iphoneos/ArchiveLeaf.app
kept_app=$ios_root/ArchiveLeaf-$timestamp-$revision.app

cleanup() {
    if [[ -d $staging_root ]]; then
        rm -rf -- $staging_root
    fi
}
trap cleanup EXIT

mkdir -p $staging_root

# Release, so the phone runs the same configuration the Mac Dogfood does. Stamped so an installed
# copy can be identified without matching it against build output.
xcodebuild build \
    -project ArchiveLeaf.xcodeproj \
    -scheme ArchiveLeaf \
    -configuration Release \
    -destination "platform=iOS,id=$device" \
    -derivedDataPath $derived_data \
    ARCHIVELEAF_SOURCE_REVISION=$revision

if [[ ! -d $built_app ]]; then
    print -u2 "Build succeeded without the expected app: $built_app"
    exit 1
fi

codesign --verify --strict --verbose=2 $built_app

stamped=$(/usr/libexec/PlistBuddy -c 'Print :ArchiveLeafSourceRevision' $built_app/Info.plist)
if [[ $stamped != $revision ]]; then
    print -u2 "Built bundle reports revision '$stamped', expected '$revision'."
    exit 1
fi

xcrun devicectl device install app --device $device $built_app

mkdir -p $ios_root
ditto $built_app $kept_app

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $kept_app/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $kept_app/Info.plist)

print "Installed ArchiveLeaf $version ($build), revision $revision"
print "Device: $device"
print "Copy:   $kept_app"

if [[ $should_launch == true ]]; then
    xcrun devicectl device process launch --terminate-existing --device $device $bundle_id
fi
