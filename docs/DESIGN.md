# ArchiveLeaf design

This is ArchiveLeaf's design record: the decisions behind the app and the reasons kept with them. For what the app is and how to build it, see the [README](../README.md).

ArchiveLeaf is a read-only personal shelf for macOS, iOS, and iPadOS. It keeps documents, media, and bookmarks immutable while letting one person organize them with folders, tags, and favorites. CloudKit Private Database is the source of truth; local caches remain disposable.

## Index

Read the sections this task needs, not the whole file. Each line says what its section answers.

- **Product direction** — what ArchiveLeaf is for, and what it deliberately does not become.
- **Current scope** — what is implemented today, and the service boundaries it is implemented behind.
- **Living design principles** — how to decide, when the answer is not already written. Read this before proposing a design.
- **Backup restore** — the `.albak` package, and why a partial restore is reported rather than rolled back.
- **Navigation** — the one canonical browsing state, and the Mac, iPad, and compact layouts derived from it.
- **The four primary areas** — Folders, Tags, Favorites, Trash: what each gathers by, what it can reach, and where a pane's title lives.
- **Rows, symbols, and counts** — where the triangle, the `>`, and the number go, and what the number counts.
- **Organization actions** — one long-press menu, one selection bar, and what decides whether an action applies.
- **Platform behavior** — measured platform constraints: no drag and drop on iOS, one drop target, the iOS 26 menu crash, the iPadOS 26 tab bar, and the standard behaviors currently locked.
- **Tags and the Trash** — tag storage, deletion, backup compatibility, and how the Trash orders and restores.
- **Browsing state** — remembering where the reader was, per device, and what changing that would take.
- **Text encoding** — detection, the manual override, and what the Shift_JIS / Windows-31J split changed.
- **Archive input** — why a ZIP is refused, the import safety limits, and how another app's bookmarks come in.
- **Wording** — the four words the interface is built from, and the Japanese collision on `アーカイブ`.
- **Version numbering**, **Deployment targets** — the version floor and why iOS 17 / macOS 14.
- **Data source** — memory vs CloudKit, how to run the test suites, when the Production schema gets deployed and what to check first, and the simulator matrix.
- **Settings layout** — the order the settings sections are in, and the rule that decides where a new one goes.
- **macOS command placement** — where intake, refresh, settings, and the destructive data actions belong.

## Product direction

ArchiveLeaf should feel like a quiet personal shelf, not an engineering tool exposing its storage machinery. The primary actions are add, view, organize, find, recover, and back up. CloudKit records, assets, hashes, import sessions, and caches are implementation details and belong only in diagnostics or advanced information.

The product favors a small set of strong organization tools: folders for one physical location, tags for cross-folder classification, favorites for quick access, and explicit sorting. It does not edit imported bytes. It also does not grow into a file converter, large-data analyzer, ZIP utility, web clipper, media editor, OCR system, or automatic AI classifier.

Privacy starts with data minimization rather than later deletion. ArchiveLeaf does not create an
app-level record of what was viewed or searched, and app-authored diagnostics must not contain a
filename, URL, path, folder or tag name, document content, page number, selection, browsing history,
CloudKit record identifier, or local asset identifier. A diagnostic event is added only for a
specific troubleshooting need and uses a fixed event name plus a reviewed coarse outcome, count,
or duration that cannot reconstruct the shelf's contents. Raw framework error descriptions are not
written to persistent logs because they may carry user data. This boundary applies before the first
log statement in a feature, not as redaction or deletion work after collection.

The confirmed direction and migration order are:

- Plain Text, Markdown, and JSON remain native document presentations. CSV-specific detection and table presentation are retired; CSV and similar decodable formats use Plain Text.
- Text import and display are limited to 10 MiB. Markdown rendering and JSON formatting are limited to 2 MiB; larger accepted documents use their lightweight source presentation.
- JPEG and PNG remain native. MP4, MOV, and M4V playback is read-only through Apple media frameworks, without conversion or editing.
- Bookmarks are first-class shelf items. `.webloc` import, direct HTTP/HTTPS entry, shared URLs, and dropped URLs store the standard property-list file as an immutable asset and never download the page.
- Quick Look remains a future fallback, not a current capability, for safe ordinary files without a native ArchiveLeaf presentation. Unsupported executables, packages, symbolic links, unsafe inputs, and oversized files remain rejected.
- Direct ZIP import is retired. Users expand third-party archives outside ArchiveLeaf and import the resulting folder. Backup and restore use a versioned `.albak` package.
- The forced visible `Import yyyy-MM-dd HH-mm-ss` folder is retired. Loose files go directly into the chosen folder and imported folders preserve their own root. No import-session metadata is recorded; nothing so far has needed it.
- Tags, in-document search for Plain Text, Markdown, JSON, and legacy CSV presentations, and a Share Extension inbox are implemented. Mac supports Finder file drops and internal dragging. iOS and iPadOS intentionally take input through the import button and the Share Extension rather than in-app drag and drop. The Share Extension stages input only in its temporary directory, then validates and writes immutable input directly to CloudKit; durable staging in the App Group remains a reliability improvement rather than a prerequisite for supported sharing.
- Slash-separated tag names form a presentation-only outline (`Dev/Xcode/iOS` → `Dev` / `Xcode` / `iOS`) on every platform. CloudKit and backups still store one tag and one name; intermediate nodes are derived, so this feature requires no data migration.
- Read-only MP4 and QuickTime movie playback uses the system AVKit player. Video import and display share the independent `ImportPolicy.maximumVideoSize` limit (200 MB by default), so the limit can change without altering stored records or the CloudKit schema. The 500 MB batch limit still applies when several files are imported together. ArchiveLeaf does not transcode unsupported codecs or generate video thumbnails.

- Read-only PDF viewing uses the system PDFKit view, which brings the scrolling, magnification, and page handling with it. PDF import and display share the independent `ImportPolicy.maximumPDFSize` limit (50 MB by default), on the same terms as video: the limit can change without altering stored records or the CloudKit schema, and the 500 MB batch limit still applies to a group. A PDF is stored and handed on exactly as imported — nothing is converted, flattened, re-rendered, or read for text. An encrypted PDF is refused at import rather than filed as a document that shows nothing, because the app has nowhere to ask for a password. Unlike a movie, a PDF does get a thumbnail: its first page is drawn onto white, at the same size and through the same versioned cache keys as an image's. A PDF carries two stated magnifications rather than the picture viewer's four — the whole page, and the page as wide as the pane — because PDFKit's pinch already covers stepping in and out, and "actual size" on paper means the page's own size rather than the screen's. The initial view, Fit Page, and Fit Width all retain PDFKit's continuous vertical column. Fit Page chooses the smaller of the width-fit and height-fit scales; Fit Width keeps the reader's vertical place. Both centre the current page horizontally. Mixed-size pages expose a PDFKit limitation here: its public navigation API positions the continuous document rather than one page within that document, so the platform adapter applies one isolated horizontal correction to PDFKit's own scroll view after measuring the current page in view coordinates. Remove that correction if PDFKit gains a public current-page centring operation.

Video payloads continue to use the same CloudKit-backed storage as every other archived file. A
local-only payload mode is deliberately deferred: it would make cross-device availability,
uninstallation, backup, and deletion semantics visible to the user. Reconsider it only if measured
CloudKit transfer behaviour remains a problem with the 200 MB per-video policy.

Compatibility is removed deliberately rather than accidentally. The legacy `csv` format value remains readable until existing Development records are no longer needed. ZIPFoundation and its extraction workflow have been removed now that the backup package covers whole-archive transfer; ArchiveLeaf has no external package dependencies.

### Backup package contract

`.albak` is a directory package, not a ZIP archive. Its initial on-disk shape is `manifest.json` plus an `Assets` directory containing one immutable payload per file, named from the file UUID. The manifest carries the original names, hierarchy, tags, payload mapping, a format identifier, and an integer schema version. The payload bytes can be recovered outside ArchiveLeaf, but reconstructing their names and organization requires interpreting that manifest; individual file sharing instead hands another app an ordinarily named file.

The extension is `albak`, and it replaced `archiveleafbackup` outright rather than being added
beside it. A package using the former extension is incompatible with the current app and is refused rather than migrated. Seventeen characters was long enough to be truncated wherever a name is given a column,
which is the one place a reader distinguishes one backup from another. A package saved by an earlier
build is dimmed in the document picker and refused by the destination check: a deliberate break,
taken while the only backups in existence are the author's own.

The new extension required a new exported UTI, `io.github.inadaman.ArchiveLeaf.albak`. **An exported
type's tag specification cannot be changed once it has been registered.** Every copy of the app ever
built still declares the old identifier with the old extension — archived Dogfood builds and
DerivedData products among them — and LaunchServices answers from a registration it already holds,
not from the newest bundle. Rebuilding with a changed tag under the same identifier therefore did
nothing visible except break exporting: the save panel still offered `archiveleafbackup`, and a
package written as `.albak` could not be produced at all, because the file no longer matched the
type it was being exported as (`CoreTransferable.TransferableError`). Treat any future change to a
declared type's extensions as a change of identifier. The manifest's own `format` string is a
separate, data-level identifier and stays as it is; it travels inside the package rather than
through the system's type database.

An exported package is named `ArchiveLeaf-Backup-YYYY-MM-DD-HH-MM`, stamped from the reader's own
clock rather than UTC. It carries the minute because two exports in one day are ordinary and a name
that stops at the day makes the second one a collision for the save panel to resolve. The fields are
fixed width and unlocalized, so the names sort chronologically as plain text, and there are no
spaces in it — a backup is a file that gets moved, scripted, and attached, and each of those is a
place a space has to be quoted.

Before any CloudKit mutation, restore must validate the complete manifest, unique identifiers, folder ancestry, completed-file state, file sizes, declared asset paths, asset existence, payload sizes, and content hashes. Validation failure reports the problem and stops without changing the archive. Export likewise excludes incomplete imports and must fail rather than silently omit an expected asset.

**A launch reads the archive once, and never reads the payloads.** The shelf and the Trash are the same records seen two ways, so `fetchContents` answers for both from one read; asking separately fetched every folder and every file three times to arrive at what the first read already held. That read asks for `fileMetadataFields` — every field except the `CKAsset` — because a query given no `desiredKeys` is asked for the payload too, and CloudKit answers by downloading it. Nothing on any screen is drawn from the asset; it is fetched one file at a time when something is opened. Deletion goes further and enumerates identity alone: emptying the Trash needs record identifiers and, to work out which items sit under a discarded folder, each record's parent and its own flag — never a name, a date, or a payload.

**Do not save a record that was fetched with `desiredKeys`.** CloudKit clears the fields the fetch omitted, which for a file record means erasing the file. The read-modify-write paths — `save(file:)`, `save(files:)` — therefore fetch whole records on purpose, and pay for the payload to change a star. That cost is known and left in place; removing it means not reading the record at all, which no current API makes safe.

**Restore writes rather than saves.** An ordinary save fetches the record before writing it, because it exists to change what is already there. Restore begins from an archive it has just found empty, so every one of those fetches was a round trip spent confirming that nothing is nothing — half the cost of a restore, with every answer known in advance. `createInEmptyArchive` is the separate path that skips the read and writes in batches; files go in smaller batches than folders and tags, since each carries a payload and the limit that matters there is bytes rather than records. A restore that is refused stops rather than continuing, because a restore is one intention and not a list of separate ones — unlike a multiple selection, where `save(files:)` reports each failure and lets the rest stand. What it managed to write stays in place and the count is reported, taken from what the service accepted rather than from the size of the batch: the private database's default zone does not honour atomic writes, so part of a batch can land.

**Every byte is digested once per operation, and the design keeps it that way.** Validating a package walks every asset and hashes all of it, so a second pass costs the size of the whole archive to learn nothing. Restore therefore takes an `ArchiveBackupRestorePlan`, a value only `prepareRestore` can produce: the type carries the validation forward across the reader's confirmation, so `restore` never re-reads the package. What `restore` does ask again is whether the archive is still empty, because another device can write into it during that confirmation — and an empty archive is the cheap question, since every one of those reads comes back with nothing. Export digests only the copy it has written, never the source as well: a copy matching the file's recorded content hash proves the source was intact and the copy faithful in one pass, as a copy of corrupt bytes fails the same comparison. Sizes are still checked against the source first, since that is metadata and turns a bad file back before its bytes are copied.

Portable backups contain completed, non-trashed items only. Trash and incomplete imports are excluded deliberately. Restore requires an entirely empty Archive, including an empty Trash; ArchiveLeaf does not merge backups into existing data. Package creation uses a temporary sibling directory and only moves a fully validated package into place, so a failed export does not leave a destination that looks complete.

The package service validates every asset as a regular non-symbolic-link file, checks its exact size and streaming SHA-256 digest, and rejects non-empty restore destinations before any mutation. Export and empty-archive restore are connected to the shared Settings UI and have completed a CloudKit Development round trip on iPhone. Restore deliberately does not merge into a non-empty archive.

## Current scope

- One multiplatform application target for macOS, iPhone, and iPad
- Adaptive navigation: a three-pane Mac reader, a two-pane iPad landscape reader when its actual
  window is wide enough, and tab-based stacks on iPhone, narrow windows, and portrait iPad
- Archive, Favorites, and Trash navigation remains available when the active archive is empty
- Immutable metadata value types and in-memory sample data
- CloudKit Private Database record mapping, reads, and asset-backed writes
- Explicit loading, empty, iCloud-unavailable, and failure UI states
- Content-based JPEG, PNG, PDF, Plain Text, JSON, and Markdown detection, plus validated `.webloc` bookmarks; archive input is recognized only to explain why it is rejected
- Read-only import preflight with per-file and batch policy limits, asking the archive once about the whole selection
- Streaming SHA-256 duplicate detection, including matches in the app trash
- File intake on every platform: a macOS window-toolbar picker and Finder drops, plus an iOS and iPadOS picker into the folder being viewed; these use the same preflight review and immutable asset persistence, and write the accepted files as one batch. The iOS and iPadOS Share Extension is a separate entry point; neither platform offers in-app drag and drop
- Read-only Plain Text, rendered Markdown, and formatted JSON detail views; legacy CSV records open as Plain Text
- Bookmark detail that opens its page when the bookmark is chosen — including choosing the one already chosen, which is how a second look is asked for. Closing the page gives the screen back to the list where the file's screen was pushed onto it, and falls back to a card carrying the host and the full address where a pane would otherwise stand empty beside a selected row. Restoring a bookmark at launch shows that card rather than opening the page: restoring is not choosing. The `.webloc` storage extension stays out of shelf titles
- Non-destructive text display-format and text-encoding overrides from the file information popover
- Capacity-bounded device-local LRU file-content cache with usage reporting and confirmed clearing in Settings
- Disposable thumbnails derived on demand for Archive and Favorites rows — a scaled picture, or a PDF's first page drawn onto white — stored under versioned keys in the same bounded local cache
- Explicit complete-URL links opened in the platform's best browser: `SFSafariViewController` full screen on iOS and iPadOS, an in-detail WebKit pane with navigation controls on macOS. Both are reached through one decision point, and an address neither accepts is handed outside only after confirmation
- Classified in-app browser failure states with retry and default-browser fallback on macOS, where ArchiveLeaf drives the web view itself; unsupported response types explain why an external browser is needed
- Read-only in-document search with match counts and highlighted results for all supported text presentations
- Last-successful metadata snapshot fallback and cached-content-only read mode while offline, with no queued mutations
- Read-only JPEG and PNG image detail views with fit, actual-size, and relative zoom controls
- Read-only PDF detail views drawn by PDFKit as one continuous vertical column of pages; Fit Page and Fit Width change magnification and centring without changing that reading model, with both controls beside the pinch on every platform
- File metadata popover and fit-relative image zoom controls
- Shared settings shell: a standard macOS Settings scene and an iPhone/iPad settings sheet
- An optional shelf lock, off until it is asked for and carrying no password of its own: the device's own recognition stands in front of the shelf, falling back from Face ID or Touch ID to the passcode so that a failed face never shuts the reader out. iPhone and iPad close the shelf again once the reader has been away for longer than a few minutes, and cover the screen whenever the app is not in front, so the app switcher keeps no picture of it; the Mac asks once at launch and then stays open, because macOS already locks its own screen. A device with no passcode set cannot be asked, so the switch is disabled there and says why. This is a privacy screen rather than encryption: the archive is stored exactly as before and stays readable wherever iCloud is
- Local automation APIs are deferred from the release scope. The app contains no local HTTP listener, API settings, token management, or incoming-server network entitlement. Stored archive content and ordinary bookmark support are unchanged
- User-controlled CloudKit Private Database deletion with typed confirmation and post-delete archive reload
- Counted, confirmed removal of incomplete import records left behind by interrupted or failed imports
- Root-level imported files remain visible and selectable in the sidebar
- File favorites with CloudKit-backed add/remove actions and a shared Favorites list
- Confirmed permanent deletion for individual Trash items and Empty Trash, including folder subtrees and stored assets
- Trash actions that read the same on every platform: one trailing row swipe carrying Restore on iPhone and iPad, toolbar buttons on macOS, and a context menu offering Restore and Delete Permanently everywhere
- Device-local sort modes — Name, Date, Format, Size — each reversible; Name and Date apply to both kinds of direct folder child, while Format and Size sort files and leave folders in stable name order
- Tags as a cross-cutting classification: a folder answers where a file sits, a tag answers what it is about, and both resolve to the same file list
- Tag creation, renaming, deletion, and assignment on macOS, iPhone, and iPad; deleting a tag takes it off every file carrying it
- Internal drag-and-drop on macOS only: onto a folder to move, onto a tag to tag, onto Favorites to star, onto the Trash to throw away, plus Finder file drops into a folder. iOS and iPadOS have none — see `Platform behavior`
- Recursive macOS folder import with hierarchy and empty-folder preservation
- Recursive folder and file hierarchy rendered from `parentFolderID`
- Import destination picker with the selected folder as its default
- Folder creation from the New Folder control of the pane being viewed, which makes it where the reader is standing; the Mac's outline additionally offers `New Folder Inside` on a folder's context menu
- Context-menu rename and validated move workflows; original file names remain immutable
- File soft-delete and restore, with `Recovered Items` fallback when the original folder is unavailable
- Root-only folder soft-delete preserves descendant relationships for whole-subtree restoration
- Duplicate rejection across both the current selection and stored completed files, per file rather than per selection
- Indexed CloudKit duplicate lookup through `ArchiveFile.contentHash`, one query for a whole import
- Immediate same-session duplicate protection while CloudKit query indexes converge
- Protocol boundaries for import, format detection, cache, and archive extraction

## Living design principles

These are the current defaults for design and implementation, not permanent rules. Implementation work can reveal constraints that justify changing them. When a principle changes, update this section with the reason and affected behavior instead of silently preserving an outdated assumption.

- Prefer the smallest data structure and control flow that satisfies the known requirement.
- Preserve semantic roles before adjusting appearance. A title remains a title, an archive item
  remains an item, and an action remains an action; do not place unlike objects in one section,
  row, group, or control merely to obtain convenient spacing or system chrome. First express the
  objects according to what they are, then solve excessive or insufficient space in the layout
  layer without changing their identity or interaction semantics.
- Keep one canonical browsing and organization state, containing the current scope or location, focused item or file, multi-selection, selection mode, and applicable view and sort options. SwiftUI panes and platform-specific views are projections of that state; none is the master or a synchronized subordinate. User actions apply pure, one-way transitions to the canonical state, then every view derives its presentation from the result. Never preserve behavior by bidirectionally synchronizing peer-view selections, paths, or other local state. A navigation path or history may adapt the canonical state to a platform control, but it must remain derived rather than become a second source of truth. Prefer a clean state model even when it requires a larger refactor: patch guards around competing state create update cycles and stale UI.
- Fail fast when an error, collision, unsafe input, or inconsistent state is detected. Report the cause and stop instead of guessing, silently skipping input, renaming items, or attempting elaborate automatic repair.
- Bookmark intake is the narrow naming exception: URL identity is decided from the immutable `.webloc` payload, while sibling display-name collisions use Finder-style numeric suffixes (`example.com 2`, `example.com 3`). Different pages from one host must remain addable; identical URLs are still rejected by content hash.
- Capture the target of a confirmed asynchronous action by value before SwiftUI dismisses its dialog. Presentation bindings are not durable operation state and may be cleared before a spawned task begins.
- Perform validation before persistence whenever practical. CloudKit cannot provide a transaction across the entire import, so a runtime failure may leave already completed items in place; report the completed and failed boundary without adding destructive rollback machinery.
- Treat imported file contents as immutable. Metadata and hierarchy may change independently from the stored asset.
- Keep policy decisions outside format-specific mechanics. Import validation, persistence, and presentation should remain replaceable behind their existing service boundaries.
- Do not impose a small folder-depth limit on ordinary archive organization. The UI favors shallow one-folder-at-a-time navigation, while untrusted imported hierarchies use independent safety limits.
- Avoid encoding temporary policy into the models unless it represents durable archive state. This keeps a later policy change from requiring a data migration unnecessarily.
- Add abstraction only at a demonstrated change boundary. Flexibility means isolating responsibilities and recording assumptions, not predicting every future variation.
- Prefer the platform's own control over a rebuilt one. Needing to reimplement standard behaviour — in-place renaming, drop highlighting, Escape to cancel — is evidence that the foundation is wrong rather than that a patch is missing.
- Portability comes from following Apple platform conventions, not from reproducing one platform's appearance on another. Prefer SwiftUI's adaptive controls and each OS's default interaction. Add platform-specific behavior only for a verified requirement the standard control cannot satisfy; record the reason, affected platforms, maintenance cost, and condition for removing it. A future Apple-platform target should ideally build by adding the target first and addressing only demonstrated API boundaries.
- Keep iOS and iPadOS top toolbars flat. Declare each action as an independent standard toolbar item in descending priority from left to right, and let the system omit items from the right when space runs out. Do not add semantic-free groups, manual spacers, hand-built More menus, or width thresholds merely to control which toolbar items remain visible. Settings is the final item and appears only at a primary area's root. Selection actions that replace the tab bar are a separate bottom-bar mode, not part of this top-toolbar rule.
- Folder and file rows have no manual order. A folder presents its direct children as one continuous list, with folders first and files second, without section headers. Name and Date sort both kinds of child (using folder `createdAt` and file `importedAt` for Date); Format and Size sort files while folders retain stable name order. A list gathered by an attribute — favorites, a tag's files, search results — follows the same applicable file-sort rule rather than giving one file different positions in different places.
- Apply an order the app depends on rather than trusting the order a query returns. CloudKit answers in whatever order it likes, and it varies between reads.
- A new record type has no queryable index until one is added and deployed. Saving creates the type; querying it fails until `recordName` is marked queryable. Never let one type's query failure fail a read that already succeeded for the rest.
- An empty state that does not scroll cannot be pulled to refresh — which is exactly when a reader wants to check whether it is really empty. Put empty states inside something scrollable.
- Verify a change three ways every time: that it works, that it looks right, and that it can be operated — at the narrowest and widest sizes, with a selection and without.
- Take an id, not a copy, into a write. A row holds the item as it was drawn, and a tag or a star may have changed since; writing the copy back silently discards that difference, which it has done. `moveToTrash(_:)`, `toggleFavorite(_:)`, `setTag(_:on:isOn:)`, and the rename operations therefore accept identifiers only.
- Do not put `@State` on a layout that can be swapped out. An iPad crosses its layout threshold at 900 points of real width and rebuilds the view, resetting anything held inside it. Location, selection, and the current area belong to `RootView` and arrive as bindings. Before adding state, answer whether it must survive a layout change.
- Give state a speaker when more than one screen can write it. Four lists stay alive behind the tabs, so a single window-wide "is selecting" flag was cleared by whichever list reported last — a late `onDisappear` from the previous tab cancelled the selection the reader had just started on the current one. The flag names its area (`selectingSection`), only the area on screen may start, only the selecting area may end, and a report from anywhere else is dropped. This race does not reproduce under XCUITest; make it structurally impossible and pin it with unit tests instead of chasing it.
- Decide the cost of an operation at the count it will meet, while writing it. Working and working at a thousand items are different requirements, and the second cannot be added afterwards. Two costs have been measured here: a CloudKit round trip is about 550 ms, so a per-item save is about 1.1 seconds an item and an operation over a selection belongs on `save(files:)`; and a list that recomputes by walking the whole archive costs rows × items on every redraw, so it asks `ArchiveIndex` instead. A new list needs its own index; an operation that cannot be batched needs its reason written down.
- Count the round trips a loop makes, not the operations it performs. Three of them hide in plain sight and the import had all three: a question asked once per item that could be asked once for the batch; a record read before it is written when its identifier was made moments ago and cannot exist; and a read of the whole archive afterwards to discover what the code already knew. Counted against the in-memory repository, one import of twenty-four files asked seventy-five things of the archive where three would do — and in memory every one of them is free, so only a count shows it. Pin the count with a test, because a re-read put back later looks entirely correct.
- A record written in two steps needs a reason for the first step. The import wrote an empty `uploading` record and then wrote it again with its payload, which cost two round trips a file and left records no screen could show whenever it was interrupted. Nothing read the first write. A write either lands or does not; a state that exists only between two writes is a cleanup problem invented by the writer.
- State the principle, and state the reason whenever a local decision bends it — the reason is the part worth keeping. Some reasons are not rational and are recorded as such, so that a later reader, human or otherwise, does not tidy them away as inefficiency. The Trash puts the most recently discarded item at the top because that is how a real waste basket behaves; that feeling is correct and the implementation follows it.
- Tags and Favorites are not cheap because they feel like metadata. In the current schema both are attributes of the file record, so setting them over N files is N writes, the same as a move. Making them cheaper means moving membership to its own record type, which makes reading and indexing more expensive; at the scale this archive works at, batching the attribute writes is enough.

The multi-file importer validates the complete selection before persistence, then writes the accepted files as one batch. A file the archive refuses is reported by name and the rest still land; only a failure of the batch itself — the network, the account — stops the run, and what was never sent is reported as not attempted rather than left unexplained.

A file the archive already holds is one file's refusal, not the selection's. It used to fail everything selected with it: a folder containing one photo imported earlier was refused whole, and the destination folder was not even created. The same sentence is still said about that file, and everything else comes in. Two identical files inside one selection are the same case — the second is named and left out.

Imports land where the user chose. A single file goes straight into the selected folder, and a folder keeps its own root there, with its hierarchy and empty folders intact. No folder is created to represent the operation itself.

That removes the timestamped folder that used to wrap every import. It also removes the accidental uniqueness that folder provided: importing a folder whose name already exists at the destination now collides, and the import stops and reports it rather than renaming anything or hiding it under a new wrapper.

## Backup restore

Restoring writes a validated `.albak` package back through `ArchiveRepository`, so the
same code path serves CloudKit and the in-memory repository. Folders are written parents first,
then files with their assets; validation has already rejected cycles and missing parents.

Restore requires a completely empty archive, Trash included. CloudKit cannot place a whole restore
in one transaction, so a failure part-way through leaves the records already written in place.
ArchiveLeaf reports that boundary instead of deleting them back out — an automatic rollback would
itself be a destructive operation that can fail. Because the archive is no longer empty at that
point, the reported message states that `Delete My Archive…` is the way back to a state where a
retry is possible.

## Navigation

ArchiveLeaf has one canonical browsing state. Its current scope or location, focused item,
multi-selection, selection mode, and applicable view or sort options drive every navigation
surface through SwiftUI's single-source-of-truth, unidirectional data flow. Panes and compact views
are equal projections of that state rather than master and subordinate views.

On macOS, `NavigationSplitView` presents three distinct responsibilities: the sidebar shows
Archive, Favorites, and Trash scopes; the content column shows one folder at a time; and the detail
column shows the focused file. A deep imported hierarchy is therefore not expanded into a
permanently visible outline.

On iPad, a regular-width landscape container that has enough actual room for two useful panes uses
two sibling panes: the browser on the left and the viewer on the right. The browser is currently a
fixed 380-point column, chosen within the 320-point minimum and 460-point maximum design bounds;
ArchiveLeaf does not add a custom draggable divider. Maximizing the viewer hides the browser and
lets the viewer occupy the current container; restoring it returns the browser. Its content measures
the actual bounds of that visible pane — never the whole device — so a maximized viewer and a
side-by-side viewer are both laid out within the space that is actually on screen. A narrow Split
View or Stage Manager window, and a portrait iPad, deliberately use the compact reader instead.
Within the iOS and iPadOS Folders browser, screen names belong to the scrolling list rather than
the navigation bar, leaving that bar to back navigation and the flat archive commands.

On iPhone and every compact iPad container, a `TabView` exposes the same primary areas and each
tab owns its own `NavigationStack`. Archive routes contain stable folder or file IDs so replacing
CloudKit-backed metadata after a rename, move, or favorite change does not invalidate the current
path. Navigation paths or history are derived adapters for platform controls; they do not own
browsing state or synchronize bidirectionally with another view's local selection or path. The
Mac panes, the iPad browser and viewer, and the compact stacks are equal projections of the one
canonical browsing state rather than master and subordinate views.

An empty active archive does not replace the navigation shell. Trash can still contain recoverable
items after every active item was removed, so the empty state belongs inside the Archive area while
Favorites and Trash remain reachable.

Folder contents are a flat, unsectioned, continuous list of direct children: folders appear first
and files second. There is no manual order. Name and Date sort both kinds of child, using folder
`createdAt` and file `importedAt` for Date; Format and Size sort files while folders remain in
stable name order. Selection may mix multiple folders and multiple files on every platform.
Operations that reasonably apply to every selected item — including Move, Trash, and dropping the
selection onto a folder — remain available to the whole selection. Actions that do not apply to
every selected item, such as tag assignment, Favorites, the current Share action, or Rename, are
disabled for a mixed or otherwise incompatible selection. If an incompatible selection nevertheless
reaches an operation boundary, the app must warn or require confirmation; it must not silently
partially apply the action. Dropping onto a folder moves the dropped item into that folder;
dropping between rows never reorders anything. These organization actions change metadata and
placement only; they never edit imported file content.

`folderSortIndex` remains in the CloudKit schema and model, including mapper compatibility, for
existing records. The app no longer reads it to determine order or writes it during folder create,
move, or rename. No CloudKit migration or data rewrite is required. `ArchiveViewModel.selection`
remains only as compatibility state for operations such as the default import destination; it no
longer owns navigation.

## The four primary areas

A place is something every item has. An attribute is something an item may not have. That rule
decides what each area is, and what it can promise.

| Area | Gathers by | Reaches every item | Hierarchy |
|---|---|---|---|
| Folders | structure (an item's one place) | yes, Unsorted Files included | real |
| Tags | attribute (an item may have several) | no | pseudo, from `/` in the name |
| Favorites | attribute (one value, held or not) | no | none |
| Trash | state | no, it is excluded from the other three | none |

Folders shows items by their structure. Items belonging to no folder appear as Unsorted Files, a separate
section always at the top. Unsorted Files is not a special folder; it is what guarantees this area reaches
every item, and without it a file in no folder would be invisible forever.

A folder pane shows one level, the archive's own first level included. Choosing the folder heading
lists the folders at the top of the tree with Unsorted Files first among them, and no files: a file
in no folder is in Unsorted Files, and that row is where it is listed. Listing those files beside
the top-level folders as well showed one file at two levels at once, and left the heading's pane
saying something no other pane in the archive says.

Tags shows tagged items, presenting a `/` in a tag name as a pseudo-hierarchy. Untagged items do not
appear, which loses nothing, because Folders still reaches them. A tag pane shows one level: the
steps directly beneath it as rows, and the files given that step's own name. `Dev/Xcode` therefore
lists the files tagged `Dev/Xcode` and a row leading to `Dev/Xcode/macOS` — not that tag's files.

That rule is the folders' rule, and it is one rule rather than two on purpose. A parent tag used to
gather every descendant's files, which made a tag the only pane in the archive showing what was not
at the level it was showing, while a folder has never listed the files of the folders inside it. A
reader who has learnt one area should not have to learn the other.

Neither Folders nor Tags has a root node; each shows the tree itself. An empty folder remains and an
empty tag disappears — a folder is a container and exists in its own right, while a tag exists only
while something carries it. Favorites is a tag's special case, flat and with one possible value,
which is why it has neither a hierarchy nor anything corresponding to Unsorted Files. An item in the Trash
appears in none of the other three: the Trash is a state, not an attribute.

Every pane writes its own name into its content rather than into the navigation bar, through
`ArchiveTitledSection` and `archiveContentTitleChrome`. A large title in the bar shrinks as the
reader scrolls and slides up among the controls, so the top of the screen means one thing at rest
and another a moment later. The title is a section header, never a row: a list draws its group's
rounded corners around its first and last rows, and a title placed among them takes the top corner
with it. The heading type is private to that file so a title cannot be dropped in among rows. The
Mac keeps the bar's title, where the same words name the window. All four tabs begin at the same
44-point height, including the Tags tree, which asks for the bar itself rather than putting an
invisible item inside it — an item would take a slot, and a slot takes the spacing beside it.

Where the reader is, is therefore read from that title and not from the navigation bar, which now
holds controls and no name. The title carries the identifier `content-title`; ask it, not the bar.
Three navigation tests were addressing `navigationBars["Documents"]` and went red the moment the
name moved, which is the second time in this file's history that tests spelled out a label and the
label moved out from under them.

## Rows, symbols, and counts

The three platforms draw a row the same way, and one column never carries two meanings.

- The disclosure triangle is at the row's leading edge, as an outline view draws it. SwiftUI's
  `List` puts it at the trailing edge, so `DisclosureGroup` and `OutlineGroup` are not used; the
  triangle is passed to `ArchiveSourceRowLabel`. Rows without one reserve the same width, so names
  stay aligned as the hierarchy deepens.
- A trailing `>` means the screen changes, and appears only where it does — the iPhone's folder
  tree. A Mac or iPad sidebar row that changes the pane beside it does not get one.
- **A number is the number of rows that row opens onto**, for folders and tags alike: the folders and
  files in that folder, or the steps and files under that tag. One sentence for every place in the
  pane, and one a reader can check by counting what is on screen. Counting every descendant instead
  was tried and was worse — a folder holding one folder and no files of its own showed the child's
  number, which it had borrowed, and a folder reading 4 opened onto two files. A file sits in exactly
  one place, so that total is a real quantity, but it is not what the row is about; opening it is
  what answers it. Unsorted Files counts its own files, because it is not a folder and the top-level
  folders are not inside it. The Trash counts items, folders and files together, because that is what
  a reader restores.

A file's row also carries its marks: where it sits, whether it is a favourite, and each of its tags.
What those marks are and in what order is decided once, in `ArchiveRowText`, and both the phone's
`ArchiveFileLabel` and the Mac's `ArchiveItemTable` read it from there.

One mark is one line's worth or nothing. A mark that will not fit in what is left of a line is not
squeezed into it — it starts the next line whole — and a mark too long even for a whole line is
shortened from the middle, ellipsis and all, because a tag's outline ends in the name that says
most. Half a tag name on the line above would read as a tag of its own, which is the thing this
rule exists to prevent. The two platforms keep that rule by different means, and both are the means
their own text control offers. The Mac draws the marks as one run of text and takes every break
inside a mark out of it — spaces, slashes, and, for a Japanese name, the gap between any two
characters — so AppKit's own wrapping sends a mark it cannot fit to the next line; a mark wider than
the whole line is shortened before the text control ever sees it, which is why the Mac's rows have
to know their width before they are measured. The phone gives each mark its own view and places
them with `MarksRow`, a layout that follows the same rule directly.

How much is shown before it is shortened is `ArchiveRowTextPolicy`: lines for the name, lines for the
marks, and where a name gives way. One spec with two sets of numbers — the same numbers make the
platforms read alike, and different numbers are how they deliberately differ. Today the marks run to
whatever length they need on iOS, where few rows are on screen and the shelf is read closely, and
stop at three lines on the Mac, where rows of an even height are what makes a long list readable. A
name too long for its room is shortened from the middle so the extension survives; AppKit will only
do that on a single line, since its text control wraps or takes from the middle but never both, so a
Mac name is one line while an iPhone name wraps to two. Shortening a name from the end instead is the
policy's other setting, and it is what a Mac name that must wrap would have to use.

## Organization actions

Folders, Tags, and Favorites are three routes to the same file, not three kinds of file, so the
long-press menu is one component (`ArchiveItemMenu`) with one order — Move, Favorite, Tags, Rename,
Share, Trash — matching the selection bar and the tab order. A folder offers the three that apply to
it: Move, Rename, Trash. Favorite, Tags, and Share belong to one file's attributes and bytes, and a
folder is offered nothing in their place — including making a folder inside it, which was taken out
of the menu in an earlier revision. On iOS that is reached by opening the folder and pressing New Folder there,
standing in the place the new folder will be. The Mac keeps `New Folder Inside` in its outline's menu
because that outline shows the whole tree without ever opening a folder to stand inside; the
difference is in the control, not in what a folder can take. The selection bar is likewise one
component (`ArchiveSelectionBar`), and what it
may offer is answered by `ArchiveItemSelection` rather than by each screen: an item knows whether it
is trashed, so the archive's four verbs and the Trash's two are mutually exclusive and a mixed
selection can do nothing. No screen contains the sentence "hide Move because this is the Trash".

Selecting hides the tab bar, as Files and Photos do, so tabs cannot be changed mid-selection.
Selection is deliberately absent from the folder tree and the tag list — the trees themselves — from
an opened file, and disabled on an empty list.

Manual order belongs to containers. Should a hand-made order ever be added, folders and tags are
where it may go; a list gathered by an attribute never is, because the same file would then hold a
different position in each place. Nothing is arranged by hand today — no list in the app has a manual
order, and `folderSortIndex` survives only as record compatibility, read and written by nothing.

## Platform behavior

Some of these are measured constraints rather than choices, and each one cost a wrong attempt.

- **iOS and iPadOS have no in-app drag and drop, by decision.** SwiftUI's `List` takes every drag in
  its own area: a `.dropDestination` on a row, or behind the list, is never called, while the same
  modifier outside the list receives normally. The only opening `List` offers is `onInsert`, which
  inserts between rows and would show an order files do not have. `.draggable` is removed too — being
  able to lift something that can go nowhere is worse than not being able to lift it. Intake is the
  share sheet and the import button. Restoring the standard behavior means moving the tree and the
  list to `UICollectionView` with `UICollectionViewDropDelegate`, the same judgement that moved macOS
  to `NSOutlineView`.
- **A view has one drop target, and it must be the `Transferable` one.** `.onDrop` and
  `.dropDestination` on the same view replace one another, and consolidating onto `.onDrop` killed
  every path on device. The `Transferable` payload that carried this rule was removed along with iOS
  drag and drop; what survives it is the rule itself. The only SwiftUI drop left is the
  Mac's `.dropDestination(for: URL.self)` in `ArchiveFolderContentsView`, and internal dragging is
  AppKit pasteboard work inside `ArchiveSourceOutline`. Do not use `.onDrop`.
- **iOS 26 crashes when a control that opened a menu disappears because of what the menu chose.**
  Closing a menu animates it back into the control it came from (`_UIMorphable`: "Cannot morph from a
  view that is not in the hierarchy"). Choosing a display format or an encoding reloaded the document,
  which replaced the screen — toolbar included — with a spinner. File information is therefore
  presented from the screen's body as a sheet on iOS, not as a toolbar item; the Mac keeps its
  popover, where AppKit has no such constraint. Do not put a menu or a confirmation on a control that
  the choice itself rebuilds.
- **A video zooms on both platforms, but only the Mac keeps its controls while zoomed.** AVKit gives
  macOS the facility outright: `AVPlayerView.allowsMagnification` magnifies the picture and leaves
  the floating transport controls at their own size, which is QuickTime Player's behaviour.
  `AVPlayerViewController` has no counterpart — its own pinch, available only full screen, merely
  switches between fitting and filling — so iOS and iPadOS carry the controller's view on a
  `UIScrollView`. The transport controls are laid out to that view's bounds, so zooming enlarges
  them and carries them off the screen; they are therefore hidden above the fitted size, and
  enlarged is a state for looking at the picture rather than for operating the player. Panning is
  held to the picture's own edge with negative content insets measured from `videoBounds`, on
  whichever axis the picture has outgrown, because the black bands are what centres it while it
  still fits. Restoring a usable control while zoomed on iOS means building transport controls of
  our own, which is not worth what it costs.
- **The video does not zoom at all on iOS 17**, phone or tablet, and the settings are not at fault:
  the scroll view reports its limits and its pinch recognizer correctly, and the gesture never
  reaches it. `AVPlayerViewControllerContentView` carries two pinch recognizers of its own, a
  rotation and several pans, and an `AVExternalGestureRecognizerPreventer` — AVKit stops outside
  recognizers by design, and on 17 the arbitration goes its way. The same code on the same AVKit
  zooms on 26, so this changed with the OS rather than with us. Zooming is therefore a macOS and
  iOS 26 capability, and an iPad on the 17 floor simply does not have it. Whether an own pinch
  recognizer declaring simultaneous recognition can win against the preventer is untested.

- **iPadOS 26 puts the tabs in the navigation bar at regular width**, which narrows the toolbar until
  the system pushes Select, Sort, and Reload into its own "…". Forcing `horizontalSizeClass` to
  compact removes it, and is not done: the cost is larger than the gain — the iPad's popovers become
  sheets, sheets go full width on a 13-inch screen, list margins take phone proportions, the path back
  to a two-pane iPad closes, and overriding the size class is not a use the OS guarantees. This is a
  screen-size problem, and it is accepted rather than worked around.

A presentation belongs to the control that raises it, not to the screen it appears over. Settings
broke this twice and in two different ways, both found on a device and neither caught by a test.

Stacking is the first way. A view presents one `fileImporter` and answers one dialog of a kind; the
outermost one replies and the rest are dropped without warning. Settings had accumulated nine
presentations on a single form, and two things had been silently dead: restore had not opened since
the bookmark importer was attached beside it, and a failed archive deletion reported nothing at all,
because its result alert lost to the ones added after it. A `fileExporter` beside a `fileImporter`
is fine — different presentations, no contest — which is why exporting kept working and pointed at
the difference.

An `alert` carrying a `TextField` does not run its button actions on iOS 17. The typed-word
confirmation for deleting the archive was one: the alert appeared, the button took the tap, the
alert closed, and nothing happened — with the right word or the wrong one. Pressing it with the
wrong word is what settled it, because that path never reaches iCloud; it sets a message and
returns, and no message ever came, while a plain button elsewhere on the same screen raised its
alert normally. Neither the deletion nor the reporting was ever at fault. `.disabled` on such a
button is not honoured either, so the button also offered itself before the word was complete.

Nothing in this app now asks for typed input in a confirmation. The archive deletion was the only
one, and it gave the word up rather than work around the platform: a safeguard that prevents the
operation it guards is not a safeguard. Two plain confirmations replace it. Should typed input ever
be needed again, it belongs in a sheet — an ordinary view runs its actions and honours `.disabled` —
but the first question to ask is whether the typing was ever the point. Alerts stay right for a
message and for a plain yes or no.

Anchoring is the second. On iPad a `confirmationDialog` is a popover, and a popover points at the
view it is attached to. Attached to a whole scrolling form inside a sheet it had nowhere to point,
and collapsed into a strip against the top edge — the title visible, the buttons not. Alerts are
unaffected: they are centred modals with no anchor to get wrong, which is why they looked correct
throughout and made the fault look narrower than it was.

Where it is attached matters beyond contention. Moving the result alerts onto their own `Section`
fixed nothing on iPad: an alert attached to a `Section` did not reach the screen there, while a
`fileImporter` attached to one worked on Mac and iPhone. That is what was observed, not a rule about
what a `Section` is; the safe reading is that a `Section` is not a dependable place to hang a
presentation. Settings therefore carries exactly one alert, on the form itself, and every outcome —
deletion, purge, cache, backup, bookmark import — arrives through it. Five alerts of identical shape
were five chances to lose a message, and they lost the same one twice.

An alert asked for while another is dismissing is dropped, not queued. The refusal for a mistyped
confirmation is instant and hit this; it waits for the confirmation to finish leaving. Anything that
follows real work does not need the wait, since a CloudKit round trip outlasts the animation.

So each confirmation and picker is attached to its own button, one alert serves the screen, and no
view owns two of a kind. None of this is testable here: pickers and dialogs are drawn by system processes that
no UI test can drive, and the suites stayed green through both faults. When adding a presentation,
the question to answer is whose view it lands on.

Locking a standard behavior is allowed while the product is still small, but each lock is written
down here with what it costs and what returning to standard requires. Add a row when you add a lock.

| Locked | Where | Effect | To return to standard |
|---|---|---|---|
| Multiple selection in the folder tree | `allowsMultipleSelection = false` in `ArchiveSourceOutline` | Only one folder at a time | Decide first what the content column shows for two folders — the union, or nothing |
| In-place folder rename on iPad | `FolderTreeListView` (SwiftUI `List`) | iPad renames in a sheet; the Mac renames in place | Move it to an AppKit equivalent, or accept the difference deliberately |
| Drag and drop on iPhone and iPad | Not implemented | Nothing can be lifted or dropped | See the `UICollectionView` note above |
| Quick Look | Not implemented; retained as a future fallback | No preview for formats the app cannot draw | Add it only for safe ordinary files without a native presentation, as a single-item fallback with no paging |

## Tags and the Trash

A tag's name lives on the tag record, so renaming one rewrites no files. `/` is reserved as the
separator that produces the displayed pseudo-hierarchy; a stored name that predates the rule and
contains an invalid value is shown as one row rather than hidden, so it can be renamed. A tag has no
manual order — name order only.

Deleting a tag does not go through the Trash. It holds nothing of the reader's, and the only thing
that could be restored is the classification itself, so it is asked once and done. The identifier is
removed from every file carrying it before the tag record is deleted, never the other way around: an
identifier with no name behind it is the worse state to be left in.

**A tag is swept away only by the device that emptied it, and only the tags that operation touched.**
Reading the archive never deletes one. It used to: a full read compared every tag against the files
that read returned, which also tidied up empty names left by older versions. That destroyed a
reader's tags. While one device imported bookmarks, another that merely came back on screen read an
archive whose tag records had arrived and whose file records had not — CloudKit answers queries from
an index that trails its own writes — so every new name looked like a leftover and was deleted, for
both devices. Re-importing could not undo it: the bookmarks were no longer new, so the import skipped
them and made no tags. **Absence in a read is not evidence of absence, and is never grounds to
delete.** A leftover name is worth far less than a destroyed one.

What remains is deliberate and narrow. Taking a tag off the last file this device can see, or
permanently deleting the last file carrying it, still removes the record, and another device may
have put that tag on something in between. The archive cannot be asked directly — `tagIDs` carries no
queryable index, and a fresh read would trail the same way — so the answer comes from what the
device knows in the moment it was the one making the change.

Backups carry tags, and `ArchiveFile` and `ArchiveBackupManifest` implement `init(from:)` by hand so
that a backup written before tags existed still restores. A synthesized decoder treats a missing key
as a failure, which would reject those files.

The Trash is one list with the most recently discarded item at the top. It is not split by kind:
the newest item would then appear in two places, and what a reader is looking for is the one item to
bring back, not a kind. Its sort — discarded date by default, or name — belongs to the Trash alone,
is independent of the archive's own order, and returns to the default each time
(`ArchiveTrashOrder`, `ArchiveTrashArrangement`). An item in the Trash can be looked at and
inspected, and nothing else: the star and Share are withheld there, because organizing a discarded
file is a thing to do after bringing it back, not instead. Restore and Delete Permanently are all its
row and its viewer offer. Trashing a folder marks the folder, not each file inside it, and its subtree
leaves view together; restoring brings the contents back with it. A restored file returns to its
original folder if that folder still exists, and otherwise to `Recovered Items` at the root.

Change subscriptions (`CKSubscription`) are deliberately not used. The archive is re-read at launch,
when the app returns to the foreground, and on pull to refresh.

## Browsing state

Where the reader was is remembered per device (`ArchiveBrowsingStateStore`, `UserDefaults`), because
a Mac and a phone are usually in different places in the archive. The memory source does not
remember. A folder or tag that no longer exists returns that area to its top.

Should this become shared across devices, the mechanism is `NSUbiquitousKeyValueStore` — it needs no
schema and no index for a few hundred bytes, where a CloudKit record would need a new type indexed
before it could be queried. Two things are required to switch: a timestamp in the stored form, so the
newer note wins, and a decision about when it is taken in — at launch only, or on `scenePhase`
returning as well. Reading and writing are confined to `ArchiveBrowsingStateStore`, and the calls to
`RootView`'s `load()` and `save()`. Handoff (`NSUserActivity`) is a different thing: continuing
between two devices in front of you now, not finding the same place later.

## Text encoding

Detection records the encoding it recognized at import time in the immutable `sourceEncoding`.
Because detection accepts the first candidate that decodes plausibly, it can be wrong. Rather than
adding a new ambiguity heuristic, `ArchiveFile.sourceEncodingOverride` lets a user pick any
supported encoding at any time from the file information popover. The stored bytes and the recorded
detection result never change, and the override applies to files imported before it existed.

`String.Encoding.shiftJIS` on Apple platforms is CP932, not JIS X 0208, so it now backs the
`windows-31j` identifier. Strict Shift_JIS is reached through the CoreFoundation encoding instead.
The two differ both on vendor extensions Windows-31J adds, such as the circled numbers at `0x8740`,
and on shared code points: `0x8160` decodes as `〜` in Shift_JIS and `～` in Windows-31J. Detection
tries strict Shift_JIS first, so a file that stays inside JIS X 0208 is recorded as `shift_jis` and
only a file that needs the vendor extensions is recorded as `windows-31j`.

This changed what the existing `shift_jis` identifier decodes. Files imported before this change
that rely on vendor extensions now fail to decode, and files containing `0x8160` render the wave
dash rather than the fullwidth tilde. Both are corrected by choosing Windows-31J in the popover.

## Archive input

ArchiveLeaf does not expand archives. A ZIP is recognized by signature only so the import can say
why it stopped and what to do instead: expand it outside the app and import the resulting folder.
The same applies to an archive found while walking an imported folder.

Removing extraction removed the project's only external dependency. Whole-archive transfer is the
job of the backup package, and a general-purpose archive utility is outside what this product is
for.

Folder depth is not a persistent archive-model constraint. User-created and moved folders are checked for valid parents, name collisions, and cycles, but not rejected at the former fifth level. `ImportPolicy` separately defaults untrusted external-folder input to 32 folder levels and 1,024 characters per relative path, alongside the 1,000-file and 500 MB batch limits. These safety values can change without a CloudKit migration.

A PDF is recognized the same way, and by more than its header: `%PDF-` is what a truncated download
keeps, so the document is opened as well, and one that has no pages or wants a password is refused
rather than filed as a document that would show nothing.

Inspection reads files, so a file too large for any limit in the policy is refused before it is
opened. Which limit applies depends on what the file turns out to be, and finding that out means
reading it — a text candidate is decoded whole, once per candidate encoding, before it is
classified. The format-specific limit is still applied afterwards.

Inspection asks the archive once. Every accepted file is hashed locally, and the whole set of hashes
goes to CloudKit in one query per hundred rather than one query per file; hashes the session has
already seen — every file a launch read, Trash included — are answered without asking at all. A
lookup that cannot answer refuses the import rather than guessing: the archive is the only thing
that knows, and importing without asking is how a second copy gets in.

### Bookmarks from another app

Settings imports a Raindrop.io CSV export and a GoodLinks JSON export. Each lands under a folder
named after the app it came from, and its tags arrive under a first step of that same name —
`Raindrop/macOS`, `GoodLinks/00daily/0-srch`. A `macOS` tag put on here and a `macOS` tag that
arrived from Raindrop stay two separate rows. Raindrop's collections become folders under
`Raindrop`, split on `/` so a nested collection keeps its shape; GoodLinks has no folders, so
everything sits directly under `GoodLinks`. Because the tag outline is derived from one stored
name, prefixing the source needs no new field and no migration.

Only the address, title, tags, favorite, and saved date come across. Raindrop's note, excerpt,
cover image, and highlights are dropped: the shelf has nowhere to say them, and a cover would have
to be downloaded, which is the one thing bookmark handling never does. Each bookmark is written as
the same standard `.webloc` asset every other way in produces, so identical content is recognized
by the same SHA-256 the ordinary import uses — anything already on the shelf, Trash included, is
skipped rather than duplicated. Running the same export twice therefore adds nothing and reuses the
folders and tags the first run made.

This is deliberately not the ordinary import path. Neither stops at the first file it cannot take
any more, but they answer differently: the ordinary path names every refusal to the reader, which is
right for a handful of files just dropped. An export is mostly pages the shelf may already hold, so
this one counts what it skipped and reports imported, already-present, unreadable, and failed as
four separate numbers. It writes the whole export as one batch for the same reason the ordinary
import does — a bookmark written on its own was four round trips for a few hundred bytes.
Choosing the app is the reader's, not a guess from the file: both exports are plain text, and the
choice decides what the folder and the tags are about to be named.

## Wording

The interface is built from four words, and each is used where it is what is meant.

- **Archive** is all of the app's data. It is what is read, what fails, what is deleted, and what is
  exported — "Loading archive…", "Couldn't load your archive", "Delete My Archive…".
- **Folder** is how an item's structure is kept, and the name of the top of the tree. Files in no
  folder are gathered under Unsorted Files, which is the interface's own wording — write it that way
  here too, rather than inventing a second name for the same place.
- **Tag** is an attribute, not a container, which is why an empty tag cannot be created and a tag
  disappears when the device holding it lets the last file go of it.
- **Favorite** is a particular attribute, and **Trash** is the set of items holding the state of
  being about to be deleted.

In Japanese, `アーカイブ` means only the first of these; a ZIP is `圧縮ファイル`. English does not
have the collision, so `archive` stays in the source strings.

Waiting is shown in the center of the screen, through `ArchiveLoadingView`: "Loading archive…" only
while the whole archive is being read, and "Loading…" for a part of it such as the Trash.

## Version numbering

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are declared once, at project level, and no
target overrides them. Xcode gives each new target its own copy, which is how the Share Extension
came to claim 1.0 while the app was at 0.1.0 — a mismatch the App Store rejects and nothing else
notices.

The release candidate uses its intended marketing version before approval; only a replacement
upload requires a higher build number.

## Deployment targets

iOS and iPadOS 17, macOS 14. That floor is set by Observation: `@Observable` and `@Bindable` carry
the archive's state throughout, and neither exists before iOS 17 or macOS 14. Reaching further back
means replacing them with `ObservableObject`, which is a rewrite of the state layer rather than a
build setting.

The one thing that had cost a version for nothing was SwiftUI's `Tab` type, which requires iOS 18.
The compact layout uses `tabItem` instead and behaves the same.

Every target carries the same floor, the Share Extension included. Xcode creates an extension
pinned to the current SDK, which would have left the extension unusable on devices the app itself
supports.

## Data source

ArchiveLeaf uses the CloudKit private database by default. Development builds connect to the Development environment selected by their entitlement, and App Store builds to Production. Exporting a Production-signed build does not change the environment of a Development build already installed. To run with in-memory sample data instead, add this environment variable to the Xcode Run scheme:

```text
ARCHIVELEAF_DATA_SOURCE=memory
```

The sample shelf carries one of each thing whose behaviour cannot be driven without it: a Markdown
file, JSON, two bookmarks, a picture, and a four-page PDF. The PDF's pages deliberately alternate
between portrait and landscape. A document of upright pages cannot show what Fit Page and Fit Width
are for — on a page taller in proportion than the pane, they are the same magnification and the two
controls look like duplicates — and a mixed document is also the case that has to keep working,
since each command is measured against the page the reader is on rather than the document. It is
drawn at launch rather than carried as bytes.

The CloudKit integration test remains opt-in through `ARCHIVELEAF_RUN_CLOUDKIT_INTEGRATION=1` because it writes records to the Development private database.

Run the ordinary macOS unit suite with `scripts/test-macos-memory.sh`. The shared `ArchiveLeaf`
Test action supplies `ARCHIVELEAF_DATA_SOURCE=memory` to the generated `.xctestrun` host
environment; the script verifies that host environment and then runs without building. Passing a
shell environment variable directly to `xcodebuild test` is insufficient: it does not reliably
reach the app-hosted test process, which may then initialize CloudKit instead.

The shared `ArchiveLeaf` scheme contains the app and cross-platform unit tests. The separate shared `ArchiveLeafUITests` scheme contains the iOS-only UI-test target. This keeps a normal macOS Test action from attempting to launch the iOS test runner while preserving an explicit scheme for iPhone and iPad UI regression runs.

The source UI is English and `Localizable.xcstrings` supplies the Japanese localization. Fixed UI labels, confirmations, settings, import review, sort names, and display-format names are localized; archive folder names, file names, document contents, URLs, and other imported user data remain verbatim. Dynamic failures returned by services are not translated implicitly and should move to typed localized errors only when their presentation is revised.

`ArchiveLeafUITests` verifies the Trash controls on iPhone and iPad. It launches with the in-memory source and the private `ARCHIVELEAF_UI_TEST_TRASH=1` fixture, which places `Welcome.md` in Trash without touching CloudKit. Both devices use one trailing swipe: a leading swipe is the iPad's own gesture for bringing out the sidebar, and a row whose swipes mean different things on a phone and on a pad is worse than one gesture meaning the same on both. Permanent deletion stays in the context menu, and the destructive path stops after verifying its warning.

A test of something only one idiom has skips on the others, decided from the runner's device rather
than from whether the thing turned up: `ArchiveTabletTwoPaneUITests` needs the two-pane reader, which
a phone never reaches, and reporting that as a failure is how a suite stops being read. On an iPad
the same absence remains a failure.

The same UI-test target uses `ARCHIVELEAF_UI_TEST_BROWSER_FAILURE=1` to expose a private sample link and inject a deterministic connection failure without performing a real network request. WebKit error classification and cancellation ordering are covered separately by unit tests; the UI test verifies the rendered error, retry action, and default-browser fallback without opening another app. Both that test and those unit tests are macOS-only, because macOS is the only platform whose browser ArchiveLeaf renders: `SFSafariViewController` draws its own bar, reports its own failures, and offers neither for inspection.

The in-memory sample set carries one bookmark alongside the documents and the picture. A bookmark is the one item that behaves differently on all three platforms, and without one on the shelf none of that could be tried by hand.

### Deploying the Production schema

The effective signed `com.apple.developer.icloud-container-environment` entitlement selects the
CloudKit environment; Debug or Release alone does not identify it. Development test builds must
be verified with an explicit Development entitlement before use. Do not treat an omitted entitlement
as evidence that a build is safe for either environment. Production schema deployment is a prerequisite
of the first build that actually uses Production, such as a TestFlight or App Store submission or a
Developer ID export, rather than a maintenance task to perform while the schema is still moving.

Deploy late on purpose. Development can be reset back to Production's state at any time, and
Production accepts additions through `Deploy Schema Changes…` as often as needed, so nothing is
lost by waiting. What Production never allows is removal: a deployed field or record type cannot be
deleted, renamed, or retyped. Deploying early only freezes names earlier while the shape of the
archive is still changing, and a name regretted afterwards costs a vestigial field plus a migration
pass. `customDisplayName` and `hasCustomDisplayName` are the names to settle before that day, for
the reason recorded at their declarations.

Before deploying, confirm the indexes the code depends on. A record type saves without one and
answers queries with nothing, so the failure looks like an empty archive rather than an error.
`ArchiveTag` is the likeliest to be missed, because files continue to import and display while only
the tag list comes back empty.

| Index | Record types | Required by |
|---|---|---|
| `recordName` Queryable | `ArchiveFolder`, `ArchiveFile`, `ArchiveTag` | the fetch-all query, whose predicate is `true` |
| `contentHash` Queryable | `ArchiveFile` | duplicate detection |

No sortable index is needed. The repository issues no sort descriptors, because the app applies its
own order rather than trusting the order a query returns.

### Simulator validation matrix

Keep the routine simulator set intentionally small, and run it on the newest installed iOS:

- iPhone 17 Pro Max: primary iPhone UI tests and the maximum-width compact layout.
- iPhone SE (3rd generation): minimum supported-style phone layout and truncation checks.
- iPad Pro 11-inch (M5): regular-width two/three-column navigation and iPad-specific row actions.

The two phones are chosen as the extremes of the compact width, not as models. Replace either one when a wider or narrower phone ships; an intermediate size adds nothing, which is why iPhone 17 Pro was used for spot checks but never joined the matrix. macOS is checked at the current system version. A generic iOS Simulator build does not count as a device UI validation. UI tests set their language and locale explicitly, so a global `simctl erase all` should not be required between normal test runs.

iOS 17 is the supported floor, settled once the main features were in place, and it is checked on a different schedule from the routine set rather than with a smaller set of devices. A full check — before a build goes out, and after any large feature lands — covers **both** the phone and the tablet on iOS 17, by simulator or by device: `iPhoneiOS17` and `iPadiOS17` are kept on the 17.5 runtime for exactly that, and `scripts/sim-setup.sh --device iPhoneiOS17` prepares them. This is where a difference between the two OS versions surfaces — a back button carries an identifier on 26 and none on 17, and tests written against one did not run on the other at all.

Appearance, contrast, text size, gestures, and real archive data are settled on devices and nowhere else.

The macOS app category is Utilities (`public.app-category.utilities`), matching ArchiveLeaf's role as a read-only archive viewer.

`PrivacyInfo.xcprivacy` declares the required-reason APIs used directly by the app: app-only `UserDefaults` for the selected sort mode (`CA92.1`), timestamps of user-selected import files (`3B52.1`), and timestamps of cache files inside the app container (`C617.1`). Re-audit these declarations whenever storage, settings, or file-metadata APIs change.

The destructive reset integration test is separately opt-in by adding the `ARCHIVELEAF_CLOUDKIT_RESET_INTEGRATION` Swift compilation condition for that test run. It deletes every ArchiveLeaf record in the Development private database before and after its seed verification.

The destructive individual-delete and Empty Trash integration test is opt-in through the `ARCHIVELEAF_CLOUDKIT_TRASH_PURGE_INTEGRATION` Swift compilation condition. It resets the Development private database before seeding its isolated verification records.

The destructive incomplete-import purge integration test is opt-in through the `ARCHIVELEAF_CLOUDKIT_INCOMPLETE_PURGE_INTEGRATION` Swift compilation condition. It resets the Development private database before and after seeding one completed and one `uploading` file record.

## Settings layout

Settings is one `Form` shared by every platform. Its sections are ordered by what a mistaken press
costs, descending: the top can lose nothing, and the bottom cannot be undone. Subject matter does
not decide position — Import, Backup, and cache clearing all concern "data", and they sit apart
because what they risk differs.

1. **Archive** — facts only. The two contracts the reader is trusting: contents are read-only, and
   storage is their own Private Database. Nothing here is a control.
2. **Privacy** — the shelf lock and a standard link to the published privacy policy. The link uses the system URL handler on every platform.
3. **Import Bookmarks** — another app's export comes in. It only adds; existing bookmarks are
   skipped rather than replaced.
4. **Backup** — the archive goes out and comes back. Restore reads as destructive and is not: it
   refuses a non-empty Archive before writing anything, so it can only fill an empty shelf.
5. **Local Cache** — the usage figure, and clearing it. Worded destructively, disposable in fact.
6. **Delete** — incomplete imports, then the whole archive. Nothing here is recoverable.

The usage figure includes the bounded file-content cache and disposable temporary work left by an
older build, a crash, or a forced termination. That work includes UUID-named files written by the
former in-memory repository; the shared preview directory; UUID-named backup and bookmark-import
staging directories; structurally valid packages carrying the former `.archiveleafbackup`
extension; and test-coverage directories left at the root of the app container. These objects are
recognised narrowly. Files and directories must be real, non-symbolic-link entries with the exact
name or structure ArchiveLeaf used, and must predate the current app launch. A legacy backup package
must contain only a regular `manifest.json` and an `Assets` directory. A coverage directory must
carry the exact UUID-process-counter name produced by the test runner and be either empty or contain
only regular `.profraw` files. Recursive size measurement never follows symbolic links. Clearing
the cache removes those recognised leftovers as well as the ordinary cache; it leaves unknown or
malformed content and temporary work created during the current launch alone.

These are the rules that place a new section, and the reasons worth keeping:

- Order by what is lost, not by what the action is about. A reader scanning downward should meet
  increasing consequence, so the dangerous end is the end they have to travel to.
- Do not collect every read-only row into the top section. A number is only useful beside the
  control that changes it, which is why cache usage stays in `Local Cache` rather than joining
  `Archive`. The gradient orders sections; it does not relocate a label away from its button.
- Keep a harmless destructive-looking action out of the irrecoverable section. Clearing the cache
  and deleting the archive are both red, and merging them would put an everyday button exactly
  where a mis-tap costs the most.
- Name a section for what it does, not for what it acts on. The delete section was called `Data`,
  which described its subject and warned nobody; `Delete` is what both of its buttons do.
- Every section closes with a footnote naming what survives it — what is *not* touched is the part
  a reader needs before pressing, and it is the reason a section can be read on its own.
- Adding a section costs more on macOS than it appears to: the settings window is a fixed
  480 × 480 frame. Prefer reordering or extending an existing section over a seventh one.
- An action's count says folders and files, not their sum. `ArchiveResetResult` carried both all
  along and reported "35 items" while a restore of the same archive said "9 folders and 26 files",
  which described a different thing at each end of one round trip.

Settings actions colour their labels the same way on every platform — blue, red when destructive —
while keeping each platform's own control. This bends the rule that portability comes from following
platform conventions rather than reproducing one platform's appearance on another, and it is worth
saying why. macOS draws a Form button as a bordered control and does not colour `role: .destructive`
at all, so `Delete My Archive…` was drawn exactly like `Export Backup…`: the single place where
colour carries meaning instead of style was the place the Mac dropped it. Only the label colour is
unified; the frame stays whatever the platform draws.

## macOS command placement

File intake is a global archive action. Its primary placement is the window toolbar, with a matching command in the File menu and the `Shift-Command-I` shortcut. It should not occupy permanent space at the bottom of the sidebar. When the archive is empty on macOS, the empty-state view also offers the same action as onboarding. It opens the existing picker and preflight rather than creating a separate import path. The action is labeled `ファイルを取り込む…` now that the preflight can commit a supported file.

On iOS and iPadOS, intake belongs to the folder on screen: the import control sits in that folder's toolbar and files land there. macOS keeps its window-level toolbar action, which imports into the archive root or the selected folder.

The archive is refreshed when the app returns to the foreground, because sharing happens while it
is in the background. That refresh keeps the current contents on screen and leaves them alone if it
fails, since the user did not ask to wait for it.

Pull to refresh exists alongside it, and is not merely a fallback. CloudKit answers queries from an
index that trails its own writes, and the archive can also change from another device, so there has
to be a way to ask again.

Settings are a global app destination rather than file metadata. A gear button opens the shared settings view on every platform. On macOS it uses the standard Settings scene and `Command-,`; on iPhone and iPad it is presented as a sheet.

When the CloudKit data source is selected, every build exposes `Delete My Archive…` so users can control their own private data. Debug builds operate on the Development database and distribution builds operate on the production database selected by their CloudKit entitlement. The action requires two destructive confirmations: a warning where it is pressed, then a final one asking again. It asked the reader to type `DELETE` until that safeguard became the thing preventing the deletion — the typed word needs a field, a field means an alert that does not run its buttons on iOS 17, and the archive could not be deleted at all on the floor device. Two presses of a plain confirmation cost the reader one extra tap and cannot fail that way. It enumerates ArchiveLeaf's folder, file, and tag record types in the default zone, deletes files before folders in atomic batches and the tags last, reports the completed boundary if a later batch fails, clears the session duplicate cache, and reloads the open archive after success. The count it reports stays folders and files: a tag is an attribute of what has just gone, not an item that was holding anything. Tags were left behind until the read-time tag sweep was removed, which had been quietly covering for it — an archive deleted on one device kept its tag rows on every other, and on the deleting device too as soon as it read again. It never runs automatically during app uninstall; apps receive no reliable uninstall callback.

Records whose `importState` never reached `completed` are excluded from the archive, Trash, Favorites, and duplicate matching, so such a record is storage a user cannot see or reclaim. Import no longer makes them: a file is one write, already `completed`, carrying its payload, so an interrupted import leaves nothing behind. The placeholder record that used to go first was read by nothing and cost two round trips a file. The Delete section still exposes `Remove Incomplete Imports…`, because archives written by earlier versions can hold those records and the only way to see them is from there. It reads the current count on demand rather than on every settings appearance, reports when nothing was found, and otherwise requires a destructive confirmation naming the count. It deletes only non-completed file records, never folders, completed files, or the local cache. A failing batch stops and reports the completed boundary instead of retrying.
