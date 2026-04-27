import Foundation
import ZIPFoundation

struct FingerprintPackageManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let packageID: UUID
    let packageName: String
    let exportedAt: Date
    let importedAt: Date?
    let source: String?
    let recordCount: Int
    let simhashDigest: String
    let tags: [String]

    init(
        packageID: UUID = UUID(),
        packageName: String,
        recordCount: Int,
        tags: [String] = [],
        exportedAt: Date = .now,
        importedAt: Date? = nil,
        source: String? = nil,
        simhashDigest: String = "",
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.packageID = packageID
        self.packageName = packageName
        self.exportedAt = exportedAt
        self.importedAt = importedAt
        self.source = Self.normalized(source)
        self.recordCount = recordCount
        self.simhashDigest = simhashDigest
        self.tags = Self.normalizedTags(tags)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let packageName = try container.decode(String.self, forKey: .packageName)
        let exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        let recordCount = try container.decode(Int.self, forKey: .recordCount)

        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.packageID = try container.decodeIfPresent(UUID.self, forKey: .packageID)
            ?? UUID.pitcherPlantStable(
                namespace: "fingerprint-package",
                components: [packageName, "\(recordCount)", String(exportedAt.timeIntervalSince1970)]
            )
        self.packageName = packageName
        self.exportedAt = exportedAt
        self.importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt)
        self.source = Self.normalized(try container.decodeIfPresent(String.self, forKey: .source))
        self.recordCount = recordCount
        self.simhashDigest = try container.decodeIfPresent(String.self, forKey: .simhashDigest) ?? ""
        self.tags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        tags: [String] = [],
        source: String? = nil
    ) throws {
        let normalizedTags = self.normalizedTags(tags)
        let packagedRecords = records.map { record in
            record.withMergedTags(normalizedTags)
        }
        let manifest = FingerprintPackageManifest(
            packageName: packageName,
            recordCount: packagedRecords.count,
            tags: normalizedTags,
            source: source,
            simhashDigest: simhashDigest(for: packagedRecords)
        )
        let package = FingerprintPackage(manifest: manifest, records: packagedRecords)

        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporaryURL = parent.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            let archive = try Archive(url: temporaryURL, accessMode: .create, pathEncoding: nil)
            try add(try encode(manifest), path: "manifest.json", to: archive)
            try add(try encode(package), path: "fingerprints.json", to: archive)
        }

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    func importPackage(from url: URL, additionalTags: [String] = []) throws -> FingerprintPackageImportResult {
        let package = try readPackage(from: url)
        try validate(package)
        let importTags = normalizedTags(package.manifest.tags + additionalTags)
        var skipped = 0
        let records = package.records.compactMap { record -> FingerprintRecord? in
            guard isValidSimhash(record.simhash) else {
                skipped += 1
                return nil
            }
            return record.withMergedTags(importTags)
        }
        let manifest = FingerprintPackageManifest(
            packageID: package.manifest.packageID,
            packageName: package.manifest.packageName,
            recordCount: records.count,
            tags: importTags,
            exportedAt: package.manifest.exportedAt,
            importedAt: .now,
            source: url.path,
            simhashDigest: package.manifest.simhashDigest,
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

    private func validate(_ package: FingerprintPackage) throws {
        guard package.manifest.schemaVersion <= FingerprintPackageManifest.currentSchemaVersion else {
            throw packageError(code: 2, message: "指纹包 schemaVersion \(package.manifest.schemaVersion) 高于当前支持版本 \(FingerprintPackageManifest.currentSchemaVersion)")
        }
        guard package.manifest.recordCount == package.records.count else {
            throw packageError(code: 3, message: "指纹包记录数校验失败：manifest=\(package.manifest.recordCount)，实际=\(package.records.count)")
        }
        if package.manifest.simhashDigest.isEmpty == false {
            let digest = simhashDigest(for: package.records)
            guard digest == package.manifest.simhashDigest else {
                throw packageError(code: 4, message: "指纹包 SimHash 校验失败")
            }
        }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func isValidSimhash(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 16 else { return false }
        return UInt64(trimmed, radix: 16) != nil
    }

    private func simhashDigest(for records: [FingerprintRecord]) -> String {
        let payload = records
            .map { record in
                [
                    record.id.uuidString,
                    record.filename,
                    record.simhash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "\n")

        var left: UInt64 = 1469598103934665603
        var right: UInt64 = 1099511628211
        for byte in payload.utf8 {
            left ^= UInt64(byte)
            left = left &* 1099511628211
            right ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            right = right &* 1469598103934665603
        }
        return String(format: "%016llx%016llx", left, right)
    }

    private func packageError(code: Int, message: String) -> NSError {
        NSError(
            domain: "PitcherPlant.FingerprintPackage",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
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
