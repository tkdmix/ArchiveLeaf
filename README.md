# ArchiveLeaf

ArchiveLeaf is a read-only personal shelf for macOS, iOS, and iPadOS. It keeps documents, pictures, PDFs, movies, and bookmarks exactly as they were imported, and lets one person organize them with folders, tags, and favorites. Everything is stored in the user's own iCloud private database through CloudKit; nothing is sent to the developer.

ArchiveLeaf is on the [App Store](https://apps.apple.com/app/archiveleaf/id6832365999) for iPhone, iPad, and Mac.

The decisions behind the app, and the reasons for them, are in [docs/DESIGN.md](docs/DESIGN.md).

## Versions

`main` may run ahead of the version on the App Store. Only commits that shipped on the App Store are tagged, as `v<version>`. Whether a later fix is released to the App Store is decided case by case.

## Requirements

- Xcode: built and tested with Xcode 27.2. The project was last upgraded by Xcode 26.6; whether that or any other earlier version builds it is unverified.
- Deployment targets: iOS and iPadOS 17, macOS 14.
- No external package dependencies.

## Building with your own team

The project ships with the identifiers of the App Store build. To run it on a device, or with CloudKit, you need your own Apple Developer team and your own identifiers.

1. Copy `Config/Developer.xcconfig.example` to `Config/Developer.xcconfig` and set `DEVELOPMENT_TEAM` to your team ID. `Config/Developer.xcconfig` is ignored by Git; `Config/Base.xcconfig` includes it when it exists. Without it, the project builds for the iOS Simulator. A macOS build needs a team, because the app's iCloud entitlements require development signing; without one, `xcodebuild … CODE_SIGNING_ALLOWED=NO` compiles it, but whether that unsigned app runs has not been checked.
2. Change the bundle identifiers. Every target's `PRODUCT_BUNDLE_IDENTIFIER` starts with `io.github.inadaman`: the app, the Share Extension, and the two test targets. A bundle identifier is unique across all teams, so these cannot be registered to yours.
3. Change the CloudKit container identifier, `iCloud.io.github.inadaman.ArchiveLeaf`, in all three places it is written:
   - `ArchiveLeaf/Resources/ArchiveLeaf.entitlements`
   - `ArchiveLeafShare/ArchiveLeafShare.entitlements`
   - `Shared/Services/CloudKit/CloudKitSchema.swift`

   The entitlements also carry an App Group and, in the app's entitlements, an iCloud key-value store identifier with the same prefix. Change those as well; the app does not currently use either.
4. Do not change the exported type identifier `io.github.inadaman.ArchiveLeaf.albak` or the backup format identifier. They identify the backup file format, not the developer, and changing them makes backups incompatible.

Xcode's Signing & Capabilities pane may write `DEVELOPMENT_TEAM` back into `project.pbxproj`. Keep the team in `Config/Developer.xcconfig` instead.

## CloudKit

ArchiveLeaf reads and writes the CloudKit private database of the signed-in iCloud account. A build with your own container does not share data with the App Store version.

In the Development environment, record types are created the first time a record is saved. Queries also need indexes, which are not created automatically. Without them a query returns nothing, so the archive looks empty rather than failing. Add these in the CloudKit Console:

| Index | Record types |
|---|---|
| `recordName` Queryable | `ArchiveFolder`, `ArchiveFile`, `ArchiveTag` |
| `contentHash` Queryable | `ArchiveFile` |

The CloudKit environment is selected by the signed entitlement, not by the build configuration. Deploy the schema to Production before the first build that uses Production. See **Data source** in [docs/DESIGN.md](docs/DESIGN.md).

## Running without CloudKit

To run with in-memory sample data, add this environment variable to the Run action of the `ArchiveLeaf` scheme:

```text
ARCHIVELEAF_DATA_SOURCE=memory
```

Nothing is read from or written to iCloud in this mode.

## Tests

- macOS unit tests: `scripts/test-macos-memory.sh`. It runs the `ArchiveLeaf` scheme with the in-memory data source.
- iOS and iPadOS UI tests: `scripts/test-ios-ui.sh [device name]`, using the `ArchiveLeafUITests` scheme. `scripts/sim-setup.sh` prepares the simulators.
- CloudKit integration tests are opt-in, because they write to, and some of them delete everything in, the Development private database. See **Data source** in [docs/DESIGN.md](docs/DESIGN.md) before enabling them.

## Privacy

ArchiveLeaf collects no data. The archive stays in the user's own iCloud private database, and the app keeps no record of what was viewed or searched. The privacy policy is at <https://tkdmix.com/apps/archiveleaf/support/#privacy>.

## Support

Support for the App Store version is at <https://tkdmix.com/apps/archiveleaf/support/>.

This repository does not accept issues or pull requests.

## License

The source code is released under the MIT License. See [LICENSE](LICENSE).

The name "ArchiveLeaf" and the app icon are not covered by the license. All rights reserved.
