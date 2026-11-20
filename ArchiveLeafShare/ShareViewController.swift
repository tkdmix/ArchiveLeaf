import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Stages what was shared, then imports it into the archive before the sheet closes.
///
/// Importing here rather than on the next app launch keeps the wait where the user can judge it:
/// they know what they just shared, and can cancel if it is more than they meant. What is already
/// written stays written — a share sheet can be torn down at any moment, so the run reports how far
/// it got instead of pretending to be atomic.
final class ShareViewController: UIViewController {
    private var model = ShareStatusModel()
    private let repository = CloudKitArchiveRepository()
    private var importTask: Task<Void, Never>?
    private lazy var stagingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ArchiveLeafShare-\(UUID().uuidString)", isDirectory: true)
    private var staged: [URL] = []
    /// Items that could not be staged. Reported with the import's own failures at the end, so a
    /// mixed share says what failed once.
    private var stagingFailures: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        let host = UIHostingController(rootView: ShareStatusView(
            model: model,
            onSaveText: { [weak self] text, name in
                self?.run { try await self?.stageText(text, named: name) }
            },
            onCancel: { [weak self] in self?.importTask?.cancel() },
            onDone: { [weak self] in self?.finish() }
        ))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        run { [weak self] in try await self?.stageAttachments() }
    }

    deinit {
        try? FileManager.default.removeItem(at: stagingURL)
    }

    /// Staging and importing share one task so cancelling stops whichever is running.
    private func run(_ stage: @escaping () async throws -> Void) {
        importTask = Task { [weak self] in
            do {
                try await stage()
                guard let self, !self.staged.isEmpty else { return }
                await self.importStaged()
            } catch is NamingRequired {
                // Naming plain text is a user interaction, not a failed import. The task resumes
                // from the name form's Add button.
                return
            } catch is CancellationError {
                self?.model.state = .failed(String(localized: "Adding was cancelled."))
            } catch {
                self?.model.state = .failed(error.localizedDescription)
            }
        }
    }

    private func stageAttachments() async throws {
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        guard !attachments.isEmpty else {
            model.state = .failed(String(localized: "There was nothing to add."))
            return
        }

        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let snapshot = try await repository.fetchSnapshot()
        var usedRootNames = Set(snapshot.files.filter { $0.parentFolderID == nil }.map(\.displayName))
        var sharedText: String?
        var failures: [String] = []
        // One share of one page can arrive twice — Firefox Focus hands over the address and a
        // second attachment that is the same address again. Two bookmarks of the same URL hold
        // identical bytes, so the second was refused as a duplicate and a plain share ended in
        // "Partly Added". The same page shared once is one bookmark.
        var stagedAddresses = Set<String>()
        for attachment in attachments {
            // Providers disagree about whether a page is a URL or plain text. Prefer concrete
            // content and explicit URLs; only interpret text after those representations fail.
            if try await stageFile(from: attachment) {
                continue
            } else if let remoteURL = try await attachment.loadWebURL() {
                do {
                    try stageBookmark(
                        from: remoteURL,
                        usedNames: &usedRootNames,
                        stagedAddresses: &stagedAddresses
                    )
                } catch {
                    failures.append(error.localizedDescription)
                }
            } else if let text = try await attachment.loadSharedText() {
                if let remoteURL = SharedURLInterpretation.webURL(from: text) {
                    do {
                        try stageBookmark(
                            from: remoteURL,
                            usedNames: &usedRootNames,
                            stagedAddresses: &stagedAddresses
                        )
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                } else if sharedText == nil {
                    sharedText = text
                }
            }
        }

        // Browsers may publish a URL plus a redundant page-title attachment. Once useful content
        // was staged, that text is metadata rather than a second archive item.
        if staged.isEmpty, let sharedText {
            model.state = .namingText(NameSuggestion.fileName(forSharedText: sharedText), text: sharedText)
            throw NamingRequired()
        }
        guard !staged.isEmpty else {
            model.state = .failed(
                failures.first
                    ?? String(localized: "None of the shared items could be read as a file.")
            )
            return
        }
        stagingFailures = failures
    }

    /// A shared page is a bookmark, not an instruction to download arbitrary bytes from the web.
    private func stageBookmark(
        from remoteURL: URL,
        usedNames: inout Set<String>,
        stagedAddresses: inout Set<String>
    ) throws {
        // Silently, not as a failure: the reader shared one page, so a second copy of it is the
        // provider repeating itself rather than something that could not be added.
        guard stagedAddresses.insert(remoteURL.absoluteString).inserted else { return }
        let itemDirectory = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let title = BookmarkDocument.uniqueTitle(for: remoteURL, among: usedNames)
        staged.append(try BookmarkDocument.write(url: remoteURL, title: title, into: itemDirectory))
        usedNames.insert(title)
    }

    private func stageText(_ text: String, named name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let destination = stagingURL.appendingPathComponent("\(trimmed).txt", isDirectory: false)
        try Data(text.utf8).write(to: destination, options: .atomic)
        staged.append(destination)
    }

    private func importStaged() async {
        model.state = .importing(completed: 0, total: staged.count)
        let service = SharedItemImportService(repository: repository)
        do {
            let result = try await service.importFiles(at: staged) { [weak self] progress in
                self?.model.state = .importing(
                    completed: progress.completed,
                    total: progress.total
                )
            }
            report(result)
        } catch {
            model.state = .failed(error.localizedDescription)
        }
    }

    private func report(_ result: SharedItemImportService.Result) {
        let reasons = stagingFailures + result.failures.map(\.reason)
        if result.importedCount == 0 {
            let reason = result.wasCancelled
                ? String(localized: "Adding was cancelled.")
                : reasons.first ?? String(localized: "None of the shared items could be added.")
            model.state = .failed(reason)
            return
        }
        // Anything that did not make it has to be said, even though most of the run succeeded.
        guard reasons.isEmpty, !result.wasCancelled else {
            model.state = .partiallyAdded(
                imported: result.importedCount,
                reason: result.wasCancelled
                    ? String(localized: "Adding was cancelled.")
                    : reasons.joined(separator: "\n")
            )
            return
        }
        model.state = .added(result.importedCount)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            finish()
        }
    }

    /// - Returns: whether the attachment was something this could copy.
    private func stageFile(from attachment: NSItemProvider) async throws -> Bool {
        // Photos hands over image data, not a file URL, so asking only for `public.fileURL`
        // rejected every picture. Take the first representation that is bytes on disk.
        //
        // `public.url` conforms to `public.data` as well, and a provider that lists it first would
        // otherwise win the race — writing a file containing the address instead of the picture it
        // points at. A remote address is not content. A file URL is left in: it resolves to the
        // bytes themselves, which is how anything shared from Files arrives.
        guard let typeIdentifier = attachment.registeredTypeIdentifiers.first(where: {
            guard let type = UTType($0), type.conforms(to: .data) else { return false }
            return !type.conforms(to: .url) || type.conforms(to: .fileURL)
        }) else {
            return false
        }
        let itemDirectory = stagingURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        try await attachment.copyFileRepresentation(
            ofType: typeIdentifier,
            suggestedName: attachment.suggestedName
        ) { temporaryURL, fileName in
            let destination = itemDirectory.appendingPathComponent(fileName, isDirectory: false)
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            self.staged.append(destination)
        }
        return true
    }

    private func finish() {
        try? FileManager.default.removeItem(at: stagingURL)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

/// Stops the staging run so the user can name the text; importing resumes from the name field.
private struct NamingRequired: Error {}

enum ShareInboxError: LocalizedError {
    case unreadableAttachment

    var errorDescription: String? {
        switch self {
        case .unreadableAttachment:
            String(localized: "That item could not be read.")
        }
    }
}

private extension NSItemProvider {
    /// - Returns: the shared text, or nil when the attachment is a file rather than a selection.
    ///
    /// A file's own text content is not this: those arrive as `public.fileURL` and already have a
    /// name, so they go down the copy path untouched.
    func loadSharedText() async throws -> String? {
        guard !hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.plainText.identifier) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = value as? String {
                    continuation.resume(returning: text)
                } else if let data = value as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: ShareInboxError.unreadableAttachment)
                }
            }
        }
    }

    /// - Returns: the web address this attachment stands for, or nil when it is not one.
    ///
    /// File URLs are excluded: those already resolve to bytes and go down the copy path.
    func loadWebURL() async throws -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.url.identifier),
              !hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: UTType.url.identifier) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url = value as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: ShareInboxError.unreadableAttachment)
                }
            }
        }
    }

    /// The URL handed to `loadFileRepresentation` only exists for the duration of its callback,
    /// so the copy has to happen inside it rather than after awaiting a URL.
    func copyFileRepresentation(
        ofType typeIdentifier: String,
        suggestedName: String?,
        using copy: @escaping (URL, String) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            _ = loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareInboxError.unreadableAttachment)
                    return
                }
                do {
                    try copy(url, Self.fileName(for: url, suggestedName: suggestedName))
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Photos names its temporary file usefully; other providers can hand over something generic,
    /// where the app's own suggestion is the better label.
    private static func fileName(for url: URL, suggestedName: String?) -> String {
        let temporaryName = url.lastPathComponent
        guard let suggestedName, !suggestedName.isEmpty else { return temporaryName }
        let suggestedExtension = (suggestedName as NSString).pathExtension
        if suggestedExtension.isEmpty, !url.pathExtension.isEmpty {
            return "\(suggestedName).\(url.pathExtension)"
        }
        return suggestedName
    }
}

@Observable
final class ShareStatusModel {
    enum State {
        case staging
        case namingText(String, text: String)
        case importing(completed: Int, total: Int)
        case added(Int)
        case partiallyAdded(imported: Int, reason: String)
        case failed(String)
    }

    var state: State = .staging
    var draftName = ""
}

private struct ShareStatusView: View {
    @Bindable var model: ShareStatusModel
    let onSaveText: (String, String) -> Void
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .staging:
                    ProgressView("Preparing…")
                case .namingText(_, let text):
                    Form {
                        Section("Name") {
                            TextField("File name", text: $model.draftName)
                        }
                        Section("Text") {
                            Text(text)
                                .lineLimit(6)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .importing(let completed, let total):
                    VStack(spacing: 16) {
                        ProgressView(value: Double(completed), total: Double(max(total, 1)))
                            .progressViewStyle(.linear)
                        Text("Adding \(completed) of \(total)…")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                case .added(let count):
                    ContentUnavailableView {
                        Label("Added to ArchiveLeaf", systemImage: "checkmark.circle")
                    } description: {
                        Text("Added \(count) items.")
                    }
                case .partiallyAdded(let imported, let reason):
                    ContentUnavailableView {
                        Label("Partly Added", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Added \(imported) items. \(reason)")
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Nothing Was Added", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Only while work is in flight: cancelling keeps whatever already landed.
                    switch model.state {
                    case .importing:
                        Button("Cancel", action: onCancel)
                    case .staging, .namingText, .added, .partiallyAdded, .failed:
                        EmptyView()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch model.state {
                    case .namingText(_, let text):
                        Button("Add") { onSaveText(text, model.draftName) }
                            .disabled(model.draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                    case .partiallyAdded, .failed:
                        Button("Done", action: onDone)
                    case .staging, .importing, .added:
                        // These end on their own; a button here would only invite a race.
                        EmptyView()
                    }
                }
            }
            .onChange(of: suggestedName) { _, name in
                if let name { model.draftName = name }
            }
        }
    }

    /// Seeds the field once the suggestion exists, without overwriting what the user then types.
    private var suggestedName: String? {
        if case .namingText(let suggestion, _) = model.state { return suggestion }
        return nil
    }
}
