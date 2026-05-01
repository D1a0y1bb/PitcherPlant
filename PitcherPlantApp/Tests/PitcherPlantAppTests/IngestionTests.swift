import Foundation
import Testing
import ZIPFoundation
@testable import PitcherPlantApp

@Test
func pdfIngestionExtractsEmbeddedImagesBeforePageFallback() throws {
    let root = try testWorkspaceRoot()
    let fixtureDirectory = root.appendingPathComponent("Fixtures/WriteupSamples/date/date6/145-flag{LNU_cyber}")

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = fixtureDirectory.path
    configuration.useVisionOCR = false

    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: fixtureDirectory)
    let pdfDocument = try #require(documents.first(where: { $0.ext == "pdf" }))

    #expect(pdfDocument.images.isEmpty == false)
    #expect(pdfDocument.images.contains(where: { $0.source.contains(":X") }))
}

@Test
func ingestionSkipsOfficeTempsAndReadsLossyText() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-ingestion-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([0xff, 0xfe, 0x66, 0x6c, 0x61, 0x67]).write(to: root.appendingPathComponent("lossy.txt"))
    try "temporary content".write(to: root.appendingPathComponent("~$draft.txt"), atomically: true, encoding: .utf8)

    let configuration = AuditConfiguration.defaults(for: root)
    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: root)

    #expect(documents.map(\.filename) == ["lossy.txt"])
    #expect(documents.first?.content.isEmpty == false)
}

@Test
func ingestionFallsBackForMislabeledTextDocxAndSkipsBrokenDocx() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-mislabeled-docx-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "plain writeup stored with docx extension".write(to: root.appendingPathComponent("plain.docx"), atomically: true, encoding: .utf8)
    try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: root.appendingPathComponent("broken.docx"))

    let configuration = AuditConfiguration.defaults(for: root)
    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: root)

    #expect(documents.map(\.filename) == ["plain.docx"])
    #expect(documents.first?.content.contains("plain writeup") == true)
}

@Test
func officeIngestionEnforcesArchiveEntryLimits() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-office-limits-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let docxURL = root.appendingPathComponent("oversized.docx")
    do {
        let archive = try Archive(url: docxURL, accessMode: .create, pathEncoding: nil)
        try addZipFile(to: archive, path: "word/document.xml", contents: String(repeating: "x", count: 4_096))
    }

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = root.path
    var limits = DocumentIngestionLimits()
    limits.maxEntryCount = 0

    do {
        _ = try DocumentIngestionService(configuration: configuration, limits: limits).ingestDocuments(in: root)
        Issue.record("Office 包条目数量超过限制时应该失败")
    } catch let error as DocumentIngestionLimitError {
        switch error {
        case .archiveEntryCountExceeded:
            break
        default:
            Issue.record("预期 Office 包条目数量限制错误，实际为 \(error)")
        }
    } catch {
        Issue.record("预期 Office 包条目数量限制错误，实际为 \(error)")
    }
}

@Test
func normalizerRemovesBoilerplateNoisePatternsDuringIngestion() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-normalizer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let noisy = "flag{secret} \(String(repeating: "a", count: 32)) \(String(repeating: "Q", count: 60)) ```print(1)``` useful evidence"
    try noisy.write(to: root.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

    let configuration = AuditConfiguration.defaults(for: root)
    let document = try #require(DocumentIngestionService(configuration: configuration).ingestDocuments(in: root).first)

    #expect(document.cleanText == "useful evidence")
}

private func addZipFile(to archive: Archive, path: String, contents: String) throws {
    let data = Data(contents.utf8)
    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
        let start = Int(position)
        let end = min(start + size, data.count)
        return data.subdata(in: start..<end)
    }
}
