import Foundation

protocol ArchiveBackupManifestCoding: Sendable {
    func encode(_ manifest: ArchiveBackupManifest) throws -> Data
    func decode(_ data: Data) throws -> ArchiveBackupManifest
}

struct JSONArchiveBackupManifestCoder: ArchiveBackupManifestCoding {
    private let validator: any ArchiveBackupManifestValidating

    init(validator: any ArchiveBackupManifestValidating = ArchiveBackupManifestValidator()) {
        self.validator = validator
    }

    func encode(_ manifest: ArchiveBackupManifest) throws -> Data {
        try validator.validate(manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    func decode(_ data: Data) throws -> ArchiveBackupManifest {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ArchiveBackupManifest.self, from: data)
        try validator.validate(manifest)
        return manifest
    }
}
