import Foundation
import CoreGraphics
import Testing
import ZIPFoundation
@testable import PitcherPlantApp

@Test
func pdfIngestionExtractsEmbeddedImagesBeforePageFallback() throws {
    let fixtureDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pitcherplant-pdf-embedded-image-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    try writePDFWithEmbeddedImage(to: fixtureDirectory.appendingPathComponent("embedded-image.pdf"))

    var configuration = AuditConfiguration.defaults(for: fixtureDirectory)
    configuration.directoryPath = fixtureDirectory.path
    configuration.useVisionOCR = false

    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: fixtureDirectory)
    let pdfDocument = try #require(documents.first(where: { $0.ext == "pdf" }))

    #expect(pdfDocument.images.isEmpty == false)
    #expect(pdfDocument.images.contains(where: { $0.source.hasPrefix("pdf-page-1:") }))
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

private func writePDFWithEmbeddedImage(to url: URL) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 180, height: 180)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil),
          let image = makeCheckerboardImage() else {
        throw CocoaError(.fileWriteUnknown)
    }

    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(mediaBox)
    context.draw(image, in: CGRect(x: 36, y: 36, width: 108, height: 108))
    context.endPDFPage()
    context.closePDF()
}

private func makeCheckerboardImage() -> CGImage? {
    let width = 8
    let height = 8
    let components = 3
    let bytesPerRow = width * components
    var pixels = [UInt8](repeating: 0, count: width * height * components)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * components
            let bright = (x + y).isMultiple(of: 2)
            pixels[offset] = bright ? 230 : 32
            pixels[offset + 1] = bright ? 72 : 180
            pixels[offset + 2] = bright ? 64 : 220
        }
    }

    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
        return nil
    }

    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8 * components,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
}
