import Foundation
import XCTest
@testable import ArchiveLeaf

#if os(macOS)
@MainActor
final class FolderImportWorkflowTests: XCTestCase {
    func testExternalFolderImportPreservesHierarchyAndEmptyFolders() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        let documents = source.appendingPathComponent("Documents", isDirectory: true)
        let empty = source.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("immutable".utf8).write(to: documents.appendingPathComponent("note.txt"))

        let repository = InMemoryArchiveRepository()
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            )
        )

        // One call now: what a drop or a menu asks for is brought in where it was aimed.
        await viewModel.inspectImports(at: [source], into: nil)
        let snapshot = await repository.fetchSnapshot()
        // The imported folder keeps its own root at the chosen destination; no operation folder
        // is wrapped around it.
        let sourceFolder = try XCTUnwrap(snapshot.folders.first(where: {
            $0.name == "Source" && $0.parentFolderID == nil
        }))

        XCTAssertTrue(snapshot.folders.contains(where: {
            $0.name == "Documents" && $0.parentFolderID == sourceFolder.id
        }))
        XCTAssertTrue(snapshot.folders.contains(where: {
            $0.name == "Empty" && $0.parentFolderID == sourceFolder.id
        }))
        XCTAssertEqual(snapshot.files.map(\.originalFileName), ["note.txt"])
        XCTAssertNil(viewModel.importErrorMessage)
    }

    /// The app's own backup is a directory. Walking into it would take it apart and file the
    /// pieces — a manifest and a folder of nameless assets — as things worth keeping.
    func testOwnBackupPackageIsRefusedRatherThanTakenApart() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let backup = workspace
            .appendingPathComponent("Archive Backup.\(ArchiveBackupPackage.pathExtension)", isDirectory: true)
        let assets = backup.appendingPathComponent(ArchiveBackupPackage.assetsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: backup.appendingPathComponent(ArchiveBackupPackage.manifestFileName))
        try Data("bytes".utf8).write(to: assets.appendingPathComponent("one.data"))

        let repository = InMemoryArchiveRepository()
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            )
        )

        await viewModel.inspectImports(at: [backup], into: nil)
        let snapshot = await repository.fetchSnapshot()

        XCTAssertTrue(snapshot.files.isEmpty)
        XCTAssertTrue(snapshot.folders.isEmpty)
        let reported = try XCTUnwrap(viewModel.importErrorMessage)
        XCTAssertTrue(reported.contains(ArchiveBackupPackage.pathExtension), reported)
    }

    /// Nothing is asked before importing, so what was refused has to be said afterwards. Silence
    /// would leave the reader believing everything came in.
    func testRefusedFilesAreReportedByNameAndReason() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let readable = workspace.appendingPathComponent("note.txt")
        let archive = workspace.appendingPathComponent("bundle.zip")
        try Data("immutable".utf8).write(to: readable)
        // A ZIP is detected by its signature and refused, rather than expanded.
        try (Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 64)).write(to: archive)

        let repository = InMemoryArchiveRepository()
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            )
        )

        await viewModel.inspectImports(at: [readable, archive], into: nil)

        let reported = try XCTUnwrap(viewModel.importErrorMessage)
        XCTAssertTrue(reported.contains("bundle.zip"), reported)
        XCTAssertFalse(reported.contains("note.txt"), reported)
        // And what was acceptable came in. One refusal used to stop everything selected with it.
        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.files.map(\.originalFileName), ["note.txt"])
    }

    /// A folder holding one file the archive already has is still imported, minus that file.
    func testFolderWithAnAlreadyArchivedFileStillLands() async throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = workspace.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let known = source.appendingPathComponent("known.txt")
        try Data("known".utf8).write(to: known)
        try Data("fresh".utf8).write(to: source.appendingPathComponent("fresh.txt"))

        let repository = InMemoryArchiveRepository()
        let viewModel = ArchiveViewModel(
            repository: repository,
            importPreflight: ImportPreflightService(
                duplicateDetector: SHA256DuplicateDetector(lookup: repository)
            )
        )
        await viewModel.inspectImports(at: [known], into: nil)
        await viewModel.inspectImports(at: [source], into: nil)

        let snapshot = await repository.fetchSnapshot()
        XCTAssertEqual(snapshot.files.map(\.originalFileName).sorted(), ["fresh.txt", "known.txt"])
        XCTAssertEqual(snapshot.folders.map(\.name), ["Source"])
        let reported = try XCTUnwrap(viewModel.importErrorMessage)
        XCTAssertTrue(reported.contains("known.txt"), reported)
    }
}
#endif
