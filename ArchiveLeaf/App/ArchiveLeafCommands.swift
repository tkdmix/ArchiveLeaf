#if os(macOS)
import SwiftUI

private struct InspectFilesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ReloadArchiveActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var inspectFilesAction: (() -> Void)? {
        get { self[InspectFilesActionKey.self] }
        set { self[InspectFilesActionKey.self] = newValue }
    }

    var reloadArchiveAction: (() -> Void)? {
        get { self[ReloadArchiveActionKey.self] }
        set { self[ReloadArchiveActionKey.self] = newValue }
    }
}

struct ArchiveLeafCommands: Commands {
    @FocusedValue(\.inspectFilesAction) private var inspectFiles
    @FocusedValue(\.reloadArchiveAction) private var reloadArchive

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("ファイルを取り込む…") {
                inspectFiles?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(inspectFiles == nil)
        }

        // Under View, where a Mac looks for reading something again, and on the shortcut every Mac
        // already knows for it.
        CommandGroup(after: .sidebar) {
            Button("アーカイブを再読み込み") {
                reloadArchive?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(reloadArchive == nil)
        }
    }
}
#endif
