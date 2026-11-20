#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_root=${script_dir:h}
# ARCHIVELEAF_BUILD_ROOT overrides where builds are kept. The default sits beside the project, outside
# the working tree, and the .noindex suffix keeps the archives out of Spotlight.
build_root=${ARCHIVELEAF_BUILD_ROOT:-${project_root:h}/ArchiveLeaf-TestBuilds.noindex}
archive_root=$build_root/Archives
current_root=$build_root/Current
should_open=false
allow_dirty=false

usage() {
    print 'Usage: scripts/build-dogfood-macos.sh [--open] [--allow-dirty]'
    print '  --open         Open the installed Dogfood build after verification.'
    print '  --allow-dirty  Permit an archive from an uncommitted working tree.'
    print 'Builds are kept in ARCHIVELEAF_BUILD_ROOT, by default ../ArchiveLeaf-TestBuilds.noindex.'
}

while (( $# > 0 )); do
    case $1 in
        --open)
            should_open=true
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

# Matched by path, not by name: the iOS Simulator runs a process called ArchiveLeaf too, and it
# has nothing to do with the Mac bundle about to be replaced.
for pid in ${(f)"$(pgrep -x ArchiveLeaf 2>/dev/null)"}; do
    executable=$(ps -o comm= -p $pid 2>/dev/null)
    if [[ -n $executable ]] && [[ $executable != */CoreSimulator/* ]]; then
        print -u2 "ArchiveLeaf is running (pid $pid). Quit the Xcode Run or Dogfood instance first."
        exit 1
    fi
done

mkdir -p $archive_root $current_root

timestamp=$(date '+%Y%m%d-%H%M%S')
revision=$(git rev-parse --short HEAD)
archive_path=$archive_root/ArchiveLeaf-$timestamp-$revision.xcarchive
staging_root=$build_root/.staging-$timestamp-$revision
staged_app=$staging_root/ArchiveLeaf.app
current_app=$current_root/ArchiveLeaf.app
replaced_app=$build_root/.replaced-$timestamp-$revision.app

cleanup() {
    if [[ -d $staging_root ]]; then
        rm -rf -- $staging_root
    fi
}
trap cleanup EXIT

# Stamped into the bundle so an installed copy can be identified without consulting Archives/.
xcodebuild archive \
    -project ArchiveLeaf.xcodeproj \
    -scheme ArchiveLeaf \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath $archive_path \
    ARCHIVELEAF_SOURCE_REVISION=$revision

archived_app=$archive_path/Products/Applications/ArchiveLeaf.app
if [[ ! -d $archived_app ]]; then
    print -u2 "Archive succeeded without the expected app: $archived_app"
    exit 1
fi

mkdir -p $staging_root
ditto $archived_app $staged_app
codesign --verify --deep --strict --verbose=2 $staged_app

if [[ -e $current_app ]]; then
    mv $current_app $replaced_app
fi

if ! mv $staged_app $current_app; then
    if [[ -e $replaced_app ]]; then
        mv $replaced_app $current_app
    fi
    exit 1
fi

if [[ -e $replaced_app ]]; then
    rm -rf -- $replaced_app
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $current_app/Contents/Info.plist)
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $current_app/Contents/Info.plist)
stamped=$(/usr/libexec/PlistBuddy -c 'Print :ArchiveLeafSourceRevision' $current_app/Contents/Info.plist)

if [[ $stamped != $revision ]]; then
    print -u2 "Installed bundle reports revision '$stamped', expected '$revision'."
    exit 1
fi

print "Installed ArchiveLeaf $version ($build), revision $revision"
print "Current: $current_app"
print "Archive: $archive_path"

if [[ $should_open == true ]]; then
    open $current_app
fi
