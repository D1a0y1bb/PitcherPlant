import AppKit
import CoreGraphics
import Foundation
import PDFKit
import ZIPFoundation

struct DocumentIngestionService {
    let configuration: AuditConfiguration

    func ingestDocuments(in directory: URL) throws -> [ParsedDocument] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var documents: [ParsedDocument] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent.hasPrefix("~$") == false else {
                continue
            }
            guard ["pdf", "docx", "md", "txt"].contains(url.pathExtension.lowercased()) else {
                continue
            }
            do {
                if let document = try parseDocument(at: url) {
                    documents.append(document)
                }
            } catch {
                if let document = parseMislabeledTextDocument(at: url, error: error) {
                    documents.append(document)
                } else {
                    print("PitcherPlant skipped unreadable document: \(url.path) (\(error.localizedDescription))")
                }
            }
        }

        return documents
    }

    private func parseDocument(at url: URL) throws -> ParsedDocument? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "txt":
            let content = try Self.readLossyText(at: url)
            return buildDocument(url: url, ext: ext, content: content, author: "", images: [])
        case "pdf":
            guard let document = PDFDocument(url: url) else { return nil }
            let content = document.string ?? ""
            let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
            let images = parsePDFImages(document: document, sourceURL: url)
            return buildDocument(url: url, ext: ext, content: content, author: author, images: images)
        case "docx":
            return try parseDocx(at: url)
        default:
            return nil
        }
    }

    private func parseDocx(at url: URL) throws -> ParsedDocument? {
        let archive = try Archive(url: url, accessMode: .read)
        var content = ""
        var author = ""
        var lastModifiedBy = ""
        var images: [ParsedImage] = []

        if let entry = archive["word/document.xml"] {
            var data = Data()
            _ = try? archive.extract(entry) { part in
                data.append(part)
            }
            content = XMLTextExtractor.plainText(from: data)
        }

        if let entry = archive["docProps/core.xml"] {
            var data = Data()
            _ = try? archive.extract(entry) { part in
                data.append(part)
            }
            author = XMLTextExtractor.metadataValue(named: "dc:creator", in: data)
            lastModifiedBy = XMLTextExtractor.metadataValue(named: "cp:lastModifiedBy", in: data)
        }

        for entry in archive where entry.path.hasPrefix("word/media/") {
            var data = Data()
            guard (try? archive.extract(entry) { part in
                data.append(part)
            }) != nil else {
                continue
            }
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

    private func parseMislabeledTextDocument(at url: URL, error: Error) -> ParsedDocument? {
        guard url.pathExtension.lowercased() == "docx",
              let data = try? Data(contentsOf: url),
              Self.isLikelyPlainText(data) else {
            return nil
        }
        let content = Self.decodeLossyText(data)
        return buildDocument(url: url, ext: "docx", content: content, author: "", images: [])
    }

    private func buildDocument(url: URL, ext: String, content: String, author: String, lastModifiedBy: String = "", images: [ParsedImage]) -> ParsedDocument {
        let normalized = content.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedDocument(
            url: url,
            filename: url.lastPathComponent,
            ext: ext,
            content: content,
            cleanText: TextNormalizer.clean(normalized),
            codeBlocks: CodeBlockExtractor.extract(from: content),
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

    private static func isLikelyPlainText(_ data: Data) -> Bool {
        guard data.isEmpty == false else {
            return true
        }
        let printable = data.filter { byte in
            byte == 0x09 || byte == 0x0a || byte == 0x0d || (byte >= 0x20 && byte != 0x7f)
        }.count
        return Double(printable) / Double(data.count) >= 0.85
    }

    private func parsePDFImages(document: PDFDocument, sourceURL: URL) -> [ParsedImage] {
        let extracted = PDFEmbeddedImageExtractor(configuration: configuration).extract(from: sourceURL)
        if extracted.isEmpty == false {
            return extracted
        }

        var images: [ParsedImage] = []
        for index in 0..<document.pageCount {
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
}

final class PDFEmbeddedImageExtractor {
    private let configuration: AuditConfiguration
    private var images: [ParsedImage] = []
    private var seenSignatures = Set<String>()

    init(configuration: AuditConfiguration) {
        self.configuration = configuration
    }

    func extract(from url: URL) -> [ParsedImage] {
        guard let document = CGPDFDocument(url as CFURL) else {
            return []
        }

        images = []
        seenSignatures = []

        for pageIndex in 1...document.numberOfPages {
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

