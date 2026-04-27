import Foundation
import Testing
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
func normalizerRemovesLegacyNoisePatternsDuringIngestion() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-normalizer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let noisy = "flag{secret} \(String(repeating: "a", count: 32)) \(String(repeating: "Q", count: 60)) ```print(1)``` useful evidence"
    try noisy.write(to: root.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)

    let configuration = AuditConfiguration.defaults(for: root)
    let document = try #require(DocumentIngestionService(configuration: configuration).ingestDocuments(in: root).first)

    #expect(document.cleanText == "useful evidence")
}
