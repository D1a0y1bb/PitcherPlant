import AppKit
import CoreGraphics
import Foundation
import PDFKit
import ZIPFoundation

protocol DocumentParser: Sendable {
    var supportedExtensions: Set<String> { get }
    func parse(_ url: URL, configuration: AuditConfiguration, limits: DocumentIngestionLimits) throws -> ParsedDocument?
}

struct DocumentIngestionLimits: Hashable, Sendable {
    var maxEntryCount: Int = 10_000
    var maxSingleFileBytes: Int64 = 256 * 1024 * 1024
    var maxTotalExpandedBytes: Int64 = 2 * 1024 * 1024 * 1024
    var maxScannedFileCount: Int = 20_000
    var maxPDFPageFallbackCount: Int = 600

    init() {}

    init(importOptions: SubmissionImportOptions) {
        maxEntryCount = importOptions.maxEntryCount
        maxSingleFileBytes = importOptions.maxSingleFileBytes
        maxTotalExpandedBytes = importOptions.maxTotalExpandedBytes
        maxScannedFileCount = importOptions.maxScannedFileCount
    }
}

enum DocumentIngestionLimitError: LocalizedError, Equatable, Sendable {
    case scannedFileCountExceeded(limit: Int)
    case fileTooLarge(path: String, bytes: Int64, limit: Int64)
    case archiveEntryCountExceeded(path: String, limit: Int)
    case archiveEntryTooLarge(path: String, bytes: Int64, limit: Int64)
    case archiveExpandedSizeExceeded(path: String, limit: Int64)
    case pdfPageCountExceeded(path: String, count: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case .scannedFileCountExceeded(let limit):
            return "扫描文件数量超过限制：\(limit)"
        case .fileTooLarge(let path, let bytes, let limit):
            return "文件大小超过限制：\(path) \(bytes)/\(limit) 字节"
        case .archiveEntryCountExceeded(let path, let limit):
            return "Office 包条目数量超过限制：\(path) \(limit)"
        case .archiveEntryTooLarge(let path, let bytes, let limit):
            return "Office 包条目大小超过限制：\(path) \(bytes)/\(limit) 字节"
        case .archiveExpandedSizeExceeded(let path, let limit):
            return "Office 包展开大小超过限制：\(path) \(limit) 字节"
        case .pdfPageCountExceeded(let path, let count, let limit):
            return "PDF 页数超过回退图片提取限制：\(path) \(count)/\(limit)"
        }
    }
}

private struct ClosureDocumentParser: DocumentParser, Sendable {
    let supportedExtensions: Set<String>
    let parseDocument: @Sendable (URL, AuditConfiguration, DocumentIngestionLimits) throws -> ParsedDocument?

    func parse(_ url: URL, configuration: AuditConfiguration, limits: DocumentIngestionLimits) throws -> ParsedDocument? {
        try parseDocument(url, configuration, limits)
    }
}

struct DocumentIngestionService {
    let configuration: AuditConfiguration
    let limits: DocumentIngestionLimits

    init(configuration: AuditConfiguration, limits: DocumentIngestionLimits = DocumentIngestionLimits()) {
        self.configuration = configuration
        self.limits = limits
    }

    private static let parserRegistry: [any DocumentParser] = [
        ClosureDocumentParser(supportedExtensions: ["md", "txt"]) { url, configuration, _ in
            let ext = url.pathExtension.lowercased()
            let content = try readLossyText(at: url)
            return DocumentIngestionService(configuration: configuration)
                .buildDocument(url: url, ext: ext, content: content, author: "", images: [])
        },
        ClosureDocumentParser(supportedExtensions: ["html", "htm"]) { url, configuration, _ in
            let ext = url.pathExtension.lowercased()
            let content = HTMLTextExtractor.plainText(from: try readLossyText(at: url))
            return DocumentIngestionService(configuration: configuration)
                .buildDocument(url: url, ext: ext, content: content, author: "", images: [])
        },
        ClosureDocumentParser(supportedExtensions: ["rtf"]) { url, configuration, _ in
            let content = readRTFText(at: url)
            return DocumentIngestionService(configuration: configuration)
                .buildDocument(url: url, ext: "rtf", content: content, author: "", images: [])
        },
        ClosureDocumentParser(supportedExtensions: ["pdf"]) { url, configuration, _ in
            try Task.checkCancellation()
            let service = DocumentIngestionService(configuration: configuration)
            guard let document = PDFDocument(url: url) else { return nil }
            try Task.checkCancellation()
            let content = document.string ?? ""
            let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
            let images = try service.parsePDFImages(document: document, sourceURL: url)
            return service.buildDocument(url: url, ext: "pdf", content: content, author: author, images: images)
        },
        ClosureDocumentParser(supportedExtensions: ["docx"]) { url, configuration, limits in
            try DocumentIngestionService(configuration: configuration, limits: limits).parseDocx(at: url)
        },
        ClosureDocumentParser(supportedExtensions: ["pptx"]) { url, configuration, limits in
            try DocumentIngestionService(configuration: configuration, limits: limits).parsePptx(at: url)
        },
        ClosureDocumentParser(supportedExtensions: imageExtensions) { url, configuration, limits in
            try DocumentIngestionService(configuration: configuration, limits: limits)
                .parseStandaloneImage(at: url, ext: url.pathExtension.lowercased())
        },
        ClosureDocumentParser(supportedExtensions: sourceCodeExtensions) { url, configuration, _ in
            let ext = url.pathExtension.lowercased()
            let content = try readLossyText(at: url)
            return DocumentIngestionService(configuration: configuration)
                .buildDocument(url: url, ext: ext, content: content, author: "", images: [], codeBlocks: [content])
        },
    ]

    func ingestDocuments(in directory: URL) throws -> [ParsedDocument] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var documents: [ParsedDocument] = []
        let supportedExtensions = Self.supportedExtensions
        var scannedFileCount = 0

        while let url = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            guard url.lastPathComponent.hasPrefix("~$") == false else {
                continue
            }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            scannedFileCount += 1
            guard scannedFileCount <= limits.maxScannedFileCount else {
                throw DocumentIngestionLimitError.scannedFileCountExceeded(limit: limits.maxScannedFileCount)
            }
            do {
                try validateFileSize(at: url)
                if let document = try parseDocument(at: url) {
                    documents.append(document)
                }
            } catch {
                if error is DocumentIngestionLimitError {
                    throw error
                }
                if let document = parseMislabeledTextDocument(at: url, error: error) {
                    documents.append(document)
                } else {
                    print("PitcherPlant skipped unreadable document: \(url.path) (\(error.localizedDescription))")
                }
            }
        }

        return documents
    }

    func preflight(in directory: URL, historicalFingerprintCount: Int) throws -> AuditRunPreflight {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let supportedExtensions = Self.supportedExtensions
        var scannedFileCount = 0
        var supportedFileCount = 0
        var totalBytes: Int64 = 0

        while let url = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            guard url.lastPathComponent.hasPrefix("~$") == false else {
                continue
            }
            scannedFileCount += 1
            guard scannedFileCount <= limits.maxScannedFileCount else {
                throw DocumentIngestionLimitError.scannedFileCountExceeded(limit: limits.maxScannedFileCount)
            }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            supportedFileCount += 1
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            totalBytes += Int64(values?.fileSize ?? 0)
        }

        return AuditRunPreflight(
            scannedFileCount: scannedFileCount,
            totalBytes: totalBytes,
            historicalFingerprintCount: historicalFingerprintCount,
            supportedFileCount: supportedFileCount
        )
    }

    private func parseDocument(at url: URL) throws -> ParsedDocument? {
        let ext = url.pathExtension.lowercased()
        guard let parser = Self.parserRegistry.first(where: { $0.supportedExtensions.contains(ext) }) else {
            return nil
        }
        return try parser.parse(url, configuration: configuration, limits: limits)
    }

    private func parseDocx(at url: URL) throws -> ParsedDocument? {
        try Task.checkCancellation()
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        var tracker = try ArchiveExtractionTracker(archive: archive, sourcePath: url.path, limits: limits)
        var content = ""
        var author = ""
        var lastModifiedBy = ""
        var images: [ParsedImage] = []

        if let entry = archive["word/document.xml"] {
            let data = try tracker.data(for: entry, in: archive)
            content = XMLTextExtractor.plainText(from: data)
        }

        if let entry = archive["docProps/core.xml"] {
            let data = try tracker.data(for: entry, in: archive)
            author = XMLTextExtractor.metadataValue(named: "dc:creator", in: data)
            lastModifiedBy = XMLTextExtractor.metadataValue(named: "cp:lastModifiedBy", in: data)
        }

        for entry in archive where entry.path.hasPrefix("word/media/") {
            try Task.checkCancellation()
            let data = try tracker.data(for: entry, in: archive)
            images.append(ParsedImage(
                source: entry.path,
                perceptualHash: ImageHashing.perceptualHash(for: data),
                averageHash: ImageHashing.averageHash(for: data),
                differenceHash: ImageHashing.differenceHash(for: data),
                ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : "",
                thumbnailBase64: ImageHashing.thumbnailBase64(for: data)
            ))
        }

        return buildDocument(url: url, ext: "docx", content: content, author: author, lastModifiedBy: lastModifiedBy, images: images)
    }

    private func parsePptx(at url: URL) throws -> ParsedDocument? {
        try Task.checkCancellation()
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        var tracker = try ArchiveExtractionTracker(archive: archive, sourcePath: url.path, limits: limits)
        var slideTexts: [(String, String)] = []
        var images: [ParsedImage] = []

        for entry in archive {
            try Task.checkCancellation()
            if entry.path.hasPrefix("ppt/slides/"), entry.path.hasSuffix(".xml") {
                let data = try tracker.data(for: entry, in: archive)
                let text = XMLTextExtractor.plainText(from: data)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    slideTexts.append((entry.path, text))
                }
            } else if entry.path.hasPrefix("ppt/media/") {
                let data = try tracker.data(for: entry, in: archive)
                images.append(parsedImage(source: entry.path, data: data))
            }
        }

        let content = slideTexts
            .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
            .map { "\($0.0)\n\($0.1)" }
            .joined(separator: "\n\n")
        return buildDocument(url: url, ext: "pptx", content: content, author: "", images: images)
    }

    private func parseStandaloneImage(at url: URL, ext: String) throws -> ParsedDocument? {
        try Task.checkCancellation()
        try validateFileSize(at: url)
        let data = try Data(contentsOf: url)
        try Task.checkCancellation()
        let image = parsedImage(source: url.lastPathComponent, data: data)
        let content = image.ocrPreview.isEmpty ? url.deletingPathExtension().lastPathComponent : image.ocrPreview
        return buildDocument(url: url, ext: ext, content: content, author: "", images: [image])
    }

    private func parseMislabeledTextDocument(at url: URL, error: Error) -> ParsedDocument? {
        guard url.pathExtension.lowercased() == "docx",
              let data = try? Data(contentsOf: url),
              Self.isLikelyPlainText(data) else {
            return nil
        }
        let content = Self.decodeLossyText(data)
        return buildDocument(url: url, ext: "docx", content: content, author: "", images: [])
    }

    private func validateFileSize(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            return
        }
        let bytes = Int64(fileSize)
        guard bytes <= limits.maxSingleFileBytes else {
            throw DocumentIngestionLimitError.fileTooLarge(
                path: url.lastPathComponent,
                bytes: bytes,
                limit: limits.maxSingleFileBytes
            )
        }
    }

    private func buildDocument(
        url: URL,
        ext: String,
        content: String,
        author: String,
        lastModifiedBy: String = "",
        images: [ParsedImage],
        codeBlocks explicitCodeBlocks: [String]? = nil
    ) -> ParsedDocument {
        let normalized = content.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let extractedCode = CodeBlockExtractor.extract(from: content)
        let codeBlocks = (explicitCodeBlocks ?? []) + extractedCode
        return ParsedDocument(
            url: url,
            filename: url.lastPathComponent,
            ext: ext,
            content: content,
            cleanText: TextNormalizer.clean(normalized),
            codeBlocks: Array(NSOrderedSet(array: codeBlocks).compactMap { $0 as? String }),
            author: author,
            lastModifiedBy: lastModifiedBy,
            images: images
        )
    }

    private static func readLossyText(at url: URL) throws -> String {
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        let data = try Data(contentsOf: url)
        return decodeLossyText(data)
    }

    private static func decodeLossyText(_ data: Data) -> String {
        if let content = String(data: data, encoding: .isoLatin1) {
            return content
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func readRTFText(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
              ) else {
            return (try? readLossyText(at: url)) ?? ""
        }
        return attributed.string
    }

    private static func isLikelyPlainText(_ data: Data) -> Bool {
        guard data.isEmpty == false else {
            return true
        }
        let printable = data.filter { byte in
            byte == 0x09 || byte == 0x0a || byte == 0x0d || (byte >= 0x20 && byte != 0x7f)
        }.count
        return Double(printable) / Double(data.count) >= 0.85
    }

    private func parsePDFImages(document: PDFDocument, sourceURL: URL) throws -> [ParsedImage] {
        let extracted = try PDFEmbeddedImageExtractor(configuration: configuration).extract(from: sourceURL)
        if extracted.isEmpty == false {
            return extracted
        }

        guard document.pageCount <= limits.maxPDFPageFallbackCount else {
            throw DocumentIngestionLimitError.pdfPageCountExceeded(
                path: sourceURL.lastPathComponent,
                count: document.pageCount,
                limit: limits.maxPDFPageFallbackCount
            )
        }
        var images: [ParsedImage] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else {
                continue
            }
            let bounds = page.bounds(for: .mediaBox)
            let thumbnail = page.thumbnail(of: CGSize(width: min(bounds.width, 360), height: min(bounds.height, 360)), for: .mediaBox)
            guard let data = thumbnail.jpegData(compressionQuality: 0.75) else {
                continue
            }
            images.append(
                ParsedImage(
                    source: "pdf-page-\(index + 1)",
                    perceptualHash: ImageHashing.perceptualHash(for: data),
                    averageHash: ImageHashing.averageHash(for: data),
                    differenceHash: ImageHashing.differenceHash(for: data),
                    ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : "",
                    thumbnailBase64: ImageHashing.thumbnailBase64(for: data)
                )
            )
        }
        return images
    }

    private func parsedImage(source: String, data: Data) -> ParsedImage {
        ParsedImage(
            source: source,
            perceptualHash: ImageHashing.perceptualHash(for: data),
            averageHash: ImageHashing.averageHash(for: data),
            differenceHash: ImageHashing.differenceHash(for: data),
            ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : "",
            thumbnailBase64: ImageHashing.thumbnailBase64(for: data)
        )
    }

    static let sourceCodeExtensions: Set<String> = [
        "py", "c", "cc", "cpp", "h", "hpp", "java", "go", "js", "jsx", "ts", "tsx",
        "swift", "sh", "bash", "zsh", "rb", "rs", "php", "cs", "kt", "sql", "m", "mm"
    ]

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp"]

    static let supportedExtensions: Set<String> = Set(parserRegistry.flatMap(\.supportedExtensions))
}

enum HTMLTextExtractor {
    static func plainText(from html: String) -> String {
        html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|li|h[1-6]|tr)>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class PDFEmbeddedImageExtractor {
    private let configuration: AuditConfiguration
    private var images: [ParsedImage] = []
    private var seenSignatures = Set<String>()

    init(configuration: AuditConfiguration) {
        self.configuration = configuration
    }

    func extract(from url: URL) throws -> [ParsedImage] {
        guard let document = CGPDFDocument(url as CFURL) else {
            return []
        }

        images = []
        seenSignatures = []

        for pageIndex in 1...document.numberOfPages {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex), let dictionary = page.dictionary else {
                continue
            }
            traverseResources(
                dictionary,
                pageIndex: pageIndex,
                prefix: "pdf-page-\(pageIndex)",
                depth: 0
            )
        }

        return images
    }

    private func traverseResources(_ dictionary: CGPDFDictionaryRef, pageIndex: Int, prefix: String, depth: Int) {
        guard depth <= 4 else {
            return
        }

        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else {
            return
        }

        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects), let xObjects else {
            return
        }

        let context = PDFXObjectTraversalContext(extractor: self, pageIndex: pageIndex, prefix: prefix, depth: depth)
        let info = Unmanaged.passRetained(context).toOpaque()
        CGPDFDictionaryApplyFunction(xObjects, pdfXObjectApplier, info)
        Unmanaged<PDFXObjectTraversalContext>.fromOpaque(info).release()
    }

    fileprivate func handleXObject(name: String, object: CGPDFObjectRef, context: PDFXObjectTraversalContext) {
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let dictionary = CGPDFStreamGetDictionary(stream) else {
            return
        }

        guard let subtype = pdfName(in: dictionary, key: "Subtype") else {
            return
        }

        let source = "\(context.prefix):\(name)"
        switch subtype {
        case "Image":
            guard let data = makeImageData(from: stream) else {
                return
            }
            let averageHash = ImageHashing.averageHash(for: data)
            let differenceHash = ImageHashing.differenceHash(for: data)
            let perceptualHash = ImageHashing.perceptualHash(for: data)
            let signature = "\(perceptualHash):\(averageHash):\(differenceHash)"
            guard seenSignatures.insert(signature).inserted else {
                return
            }
            images.append(
                ParsedImage(
                    source: source,
                    perceptualHash: perceptualHash,
                    averageHash: averageHash,
                    differenceHash: differenceHash,
                    ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : "",
                    thumbnailBase64: ImageHashing.thumbnailBase64(for: data)
                )
            )
        case "Form":
            traverseResources(dictionary, pageIndex: context.pageIndex, prefix: source, depth: context.depth + 1)
        default:
            return
        }
    }

    private func makeImageData(from stream: CGPDFStreamRef) -> Data? {
        var format = CGPDFDataFormat.raw
        guard let copied = CGPDFStreamCopyData(stream, &format) else {
            return nil
        }

        let data = copied as Data
        switch format {
        case .jpegEncoded, .JPEG2000:
            return data
        case .raw:
            return makeRasterImageData(from: data, dictionary: CGPDFStreamGetDictionary(stream))
        @unknown default:
            return nil
        }
    }

    private func makeRasterImageData(from data: Data, dictionary: CGPDFDictionaryRef?) -> Data? {
        guard let dictionary else {
            return nil
        }

        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        var bitsPerComponent: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, "Width", &width),
              CGPDFDictionaryGetInteger(dictionary, "Height", &height),
              CGPDFDictionaryGetInteger(dictionary, "BitsPerComponent", &bitsPerComponent) else {
            return nil
        }

        guard let descriptor = colorDescriptor(for: dictionary),
              width > 0,
              height > 0,
              bitsPerComponent == 8,
              data.isEmpty == false else {
            return nil
        }

        let rowCount = Int(height)
        guard rowCount > 0, data.count % rowCount == 0 else {
            return nil
        }

        let bytesPerRow = data.count / rowCount
        let expectedMinimum = Int(width) * descriptor.components
        guard bytesPerRow >= expectedMinimum else {
            return nil
        }

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: Int(width),
                height: Int(height),
                bitsPerComponent: Int(bitsPerComponent),
                bitsPerPixel: Int(bitsPerComponent) * descriptor.components,
                bytesPerRow: bytesPerRow,
                space: descriptor.colorSpace,
                bitmapInfo: descriptor.bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return ImageHashing.encodedImageData(for: image)
    }

    private func colorDescriptor(for dictionary: CGPDFDictionaryRef) -> PDFImageColorDescriptor? {
        var colorSpaceObject: CGPDFObjectRef?
        guard CGPDFDictionaryGetObject(dictionary, "ColorSpace", &colorSpaceObject), let colorSpaceObject else {
            return nil
        }

        var namedSpace: UnsafePointer<CChar>?
        if CGPDFObjectGetValue(colorSpaceObject, .name, &namedSpace), let namedSpace {
            return descriptor(for: String(cString: namedSpace))
        }

        var array: CGPDFArrayRef?
        guard CGPDFObjectGetValue(colorSpaceObject, .array, &array), let array else {
            return nil
        }

        var firstObject: CGPDFObjectRef?
        guard CGPDFArrayGetObject(array, 0, &firstObject), let firstObject else {
            return nil
        }

        var colorSpaceName: UnsafePointer<CChar>?
        guard CGPDFObjectGetValue(firstObject, .name, &colorSpaceName), let colorSpaceName else {
            return nil
        }

        let name = String(cString: colorSpaceName)
        if name == "ICCBased" {
            var profileObject: CGPDFObjectRef?
            if CGPDFArrayGetObject(array, 1, &profileObject),
               let profileObject,
               let profileStream = pdfStream(from: profileObject),
               let profileDictionary = CGPDFStreamGetDictionary(profileStream) {
                if let alternate = pdfName(in: profileDictionary, key: "Alternate"),
                   let alternateDescriptor = descriptor(for: alternate) {
                    return alternateDescriptor
                }

                var components: CGPDFInteger = 0
                if CGPDFDictionaryGetInteger(profileDictionary, "N", &components) {
                    switch components {
                    case 1:
                        return descriptor(for: "DeviceGray")
                    case 3:
                        return descriptor(for: "DeviceRGB")
                    case 4:
                        return descriptor(for: "DeviceCMYK")
                    default:
                        break
                    }
                }
            }
        }

        return descriptor(for: name)
    }

    private func descriptor(for name: String) -> PDFImageColorDescriptor? {
        switch name {
        case "DeviceGray":
            return PDFImageColorDescriptor(
                colorSpace: CGColorSpaceCreateDeviceGray(),
                components: 1,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            )
        case "DeviceRGB":
            return PDFImageColorDescriptor(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: 3,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            )
        case "DeviceCMYK":
            return PDFImageColorDescriptor(
                colorSpace: CGColorSpaceCreateDeviceCMYK(),
                components: 4,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            )
        default:
            return nil
        }
    }
}

private struct ArchiveExtractionTracker {
    private let sourcePath: String
    private let limits: DocumentIngestionLimits
    private var expandedBytes: UInt64 = 0

    init(archive: Archive, sourcePath: String, limits: DocumentIngestionLimits) throws {
        self.sourcePath = sourcePath
        self.limits = limits

        var entryCount = 0
        for entry in archive {
            try Task.checkCancellation()
            entryCount += 1
            guard entryCount <= limits.maxEntryCount else {
                throw DocumentIngestionLimitError.archiveEntryCountExceeded(
                    path: sourcePath,
                    limit: limits.maxEntryCount
                )
            }
            try Self.validateEntrySize(entry, sourcePath: sourcePath, limits: limits)
        }
    }

    mutating func data(for entry: Entry, in archive: Archive) throws -> Data {
        try Task.checkCancellation()
        try Self.validateEntrySize(entry, sourcePath: entry.path, limits: limits)
        var data = Data()
        _ = try archive.extract(entry) { part in
            try Task.checkCancellation()
            try append(part, to: &data, sourcePath: entry.path)
        }
        return data
    }

    private mutating func append(_ part: Data, to data: inout Data, sourcePath: String) throws {
        let singleLimit = UInt64(max(0, limits.maxSingleFileBytes))
        let totalLimit = UInt64(max(0, limits.maxTotalExpandedBytes))
        let partSize = UInt64(part.count)
        let currentSize = UInt64(data.count)

        guard currentSize <= singleLimit, partSize <= singleLimit - currentSize else {
            throw DocumentIngestionLimitError.archiveEntryTooLarge(
                path: sourcePath,
                bytes: Int64(currentSize + partSize),
                limit: limits.maxSingleFileBytes
            )
        }
        guard partSize <= totalLimit, expandedBytes <= totalLimit - partSize else {
            throw DocumentIngestionLimitError.archiveExpandedSizeExceeded(
                path: self.sourcePath,
                limit: limits.maxTotalExpandedBytes
            )
        }

        expandedBytes += partSize
        data.append(part)
    }

    private static func validateEntrySize(
        _ entry: Entry,
        sourcePath: String,
        limits: DocumentIngestionLimits
    ) throws {
        let singleLimit = UInt64(max(0, limits.maxSingleFileBytes))
        guard entry.uncompressedSize <= singleLimit else {
            throw DocumentIngestionLimitError.archiveEntryTooLarge(
                path: sourcePath,
                bytes: Int64(entry.uncompressedSize),
                limit: limits.maxSingleFileBytes
            )
        }
    }
}

private final class PDFXObjectTraversalContext {
    let extractor: PDFEmbeddedImageExtractor
    let pageIndex: Int
    let prefix: String
    let depth: Int

    init(extractor: PDFEmbeddedImageExtractor, pageIndex: Int, prefix: String, depth: Int) {
        self.extractor = extractor
        self.pageIndex = pageIndex
        self.prefix = prefix
        self.depth = depth
    }
}

private struct PDFImageColorDescriptor {
    let colorSpace: CGColorSpace
    let components: Int
    let bitmapInfo: CGBitmapInfo
}

private let pdfXObjectApplier: CGPDFDictionaryApplierFunction = { key, object, info in
    guard let info else {
        return
    }
    let context = Unmanaged<PDFXObjectTraversalContext>.fromOpaque(info).takeUnretainedValue()
    context.extractor.handleXObject(name: String(cString: key), object: object, context: context)
}

private func pdfName(in dictionary: CGPDFDictionaryRef, key: String) -> String? {
    var pointer: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, key, &pointer), let pointer else {
        return nil
    }
    return String(cString: pointer)
}

private func pdfStream(from object: CGPDFObjectRef) -> CGPDFStreamRef? {
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream) else {
        return nil
    }
    return stream
}
