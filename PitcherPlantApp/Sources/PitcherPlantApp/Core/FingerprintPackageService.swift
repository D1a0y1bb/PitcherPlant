import Foundation
import ZIPFoundation

struct FingerprintPackageManifest: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let packageName: String
    let exportedAt: Date
    let recordCount: Int
    let tags: [String]

    init(packageName: String, recordCount: Int, tags: [String] = [], exportedAt: Date = .now, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.packageName = packageName
        self.exportedAt = exportedAt
        self.recordCount = recordCount
        self.tags = Self.normalizedTags(tags)
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
}

struct FingerprintPackage: Codable, Hashable, Sendable {
    let manifest: FingerprintPackageManifest
    let records: [FingerprintRecord]
}

struct FingerprintPackageImportResult: Hashable, Sendable {
    let manifest: FingerprintPackageManifest
    let records: [FingerprintRecord]
    let skippedCount: Int

    var importedCount: Int {
        records.count
    }
}

struct FingerprintPackageService {
    func exportPackage(
        records: [FingerprintRecord],
        to url: URL,
        packageName: String = "PitcherPlant Fingerprints",
        tags: [String] = []
    ) throws {
        let normalizedTags = self.normalizedTags(tags)
        let packagedRecords = records.map { record in
            record.withMergedTags(normalizedTags)
        }
        let manifest = FingerprintPackageManifest(
            packageName: packageName,
            recordCount: packagedRecords.count,
            tags: normalizedTags
        )
        let package = FingerprintPackage(manifest: manifest, records: packagedRecords)

        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        try add(try encode(manifest), path: "manifest.json", to: archive)
        try add(try encode(package), path: "fingerprints.json", to: archive)
    }

    func importPackage(from url: URL, additionalTags: [String] = []) throws -> FingerprintPackageImportResult {
        let package = try readPackage(from: url)
        let importTags = normalizedTags(package.manifest.tags + additionalTags)
        var skipped = 0
        let records = package.records.compactMap { record -> FingerprintRecord? in
            guard record.simhash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                skipped += 1
                return nil
            }
            return record.withMergedTags(importTags)
        }
        let manifest = FingerprintPackageManifest(
            packageName: package.manifest.packageName,
            recordCount: records.count,
            tags: importTags,
            exportedAt: package.manifest.exportedAt,
            schemaVersion: package.manifest.schemaVersion
        )
        return FingerprintPackageImportResult(manifest: manifest, records: records, skippedCount: skipped)
    }

    private func readPackage(from url: URL) throws -> FingerprintPackage {
        if url.pathExtension.lowercased() == "json" {
            return try decode(FingerprintPackage.self, from: Data(contentsOf: url))
        }

        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        guard let entry = archive["fingerprints.json"] ?? archive["fingerprints"] else {
            throw NSError(
                domain: "PitcherPlant.FingerprintPackage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "指纹包缺少 fingerprints.json"]
            )
        }
        return try decode(FingerprintPackage.self, from: read(entry, in: archive))
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func read(_ entry: Entry, in archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { part in data.append(part) }
        return data
    }

    private func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }
}

private extension FingerprintRecord {
    func withMergedTags(_ tags: [String]) -> FingerprintRecord {
        let merged = Array(Set((self.tags ?? []) + tags)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
            .sorted()
        var copy = self
        copy.tags = merged.isEmpty ? nil : merged
        return copy
    }
}
