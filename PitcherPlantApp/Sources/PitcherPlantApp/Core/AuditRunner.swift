import AppKit
import CoreGraphics
import Foundation
import NaturalLanguage
import PDFKit
import Quartz
import Vision
import ZIPFoundation

struct AuditRunner {
    func run(
        configuration: AuditConfiguration,
        importedFingerprints: [FingerprintRecord],
        whitelistRules: [WhitelistRule],
        progress: @escaping @Sendable (AuditStage, String) -> Void
    ) async throws -> AuditRunResult {
        progress(.initialize, AuditStage.initialize.displayTitle)

        let directoryURL = URL(fileURLWithPath: configuration.directoryPath)
        let ingestion = DocumentIngestionService(configuration: configuration)
        let documents = try ingestion.ingestDocuments(in: directoryURL)
        progress(.parsed, AuditStage.parsed.displayTitle)

        let textAnalyzer = TextSimilarityAnalyzer()
        let textPairs = textAnalyzer.analyze(documents: documents, threshold: configuration.textThreshold)
        progress(.text, AuditStage.text.displayTitle)

        let codePairs = CodeSimilarityAnalyzer().analyze(documents: documents)
        progress(.code, AuditStage.code.displayTitle)

        let imagePairs = ImageReuseAnalyzer().analyze(documents: documents, threshold: configuration.imageThreshold)
        progress(.image, AuditStage.image.displayTitle)

        let metadataCollisions = MetadataCollisionAnalyzer().analyze(documents: documents)
        progress(.metadata, AuditStage.metadata.displayTitle)

        let dedupPairs = DedupAnalyzer().analyze(documents: documents, threshold: configuration.dedupThreshold)
        let currentFingerprints = FingerprintAnalyzer().buildRecords(documents: documents, scanDirectory: directoryURL.lastPathComponent)
        let crossBatch = CrossBatchReuseAnalyzer().analyze(
            current: currentFingerprints,
            historical: importedFingerprints,
            whitelistRules: whitelistRules,
            whitelistMode: configuration.whitelistMode,
            threshold: configuration.simhashThreshold
        )

        let title = directoryURL.lastPathComponent.isEmpty ? "PitcherPlant 报告" : directoryURL.lastPathComponent
        let timestamp = DateFormatter.pitcherPlantFileName.string(from: .now)
        let sourceURL = URL(fileURLWithPath: configuration.outputDirectoryPath)
            .appendingPathComponent(configuration.reportNameTemplate
                .replacingOccurrences(of: "{dir}", with: title)
                .replacingOccurrences(of: "{date}", with: timestamp))

        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let report = ReportAssembler().assemble(
            title: title,
            sourceURL: sourceURL,
            scanDirectory: directoryURL.path,
            textPairs: textPairs,
            codePairs: codePairs,
            imagePairs: imagePairs,
            metadataCollisions: metadataCollisions,
            dedupPairs: dedupPairs,
            fingerprints: currentFingerprints,
            crossBatch: crossBatch
        )
        try ReportExporter.exportHTML(report: report, to: sourceURL)
        return AuditRunResult(report: report, fingerprints: currentFingerprints)
    }
}

struct AuditRunResult {
    let report: AuditReport
    let fingerprints: [FingerprintRecord]
}

struct ParsedDocument: Hashable, Sendable {
    let url: URL
    let filename: String
    let ext: String
    let content: String
    let cleanText: String
    let codeBlocks: [String]
    let author: String
    let lastModifiedBy: String
    let images: [ParsedImage]

    init(
        url: URL,
        filename: String,
        ext: String,
        content: String,
        cleanText: String,
        codeBlocks: [String],
        author: String,
        lastModifiedBy: String = "",
        images: [ParsedImage]
    ) {
        self.url = url
        self.filename = filename
        self.ext = ext
        self.content = content
        self.cleanText = cleanText
        self.codeBlocks = codeBlocks
        self.author = author
        self.lastModifiedBy = lastModifiedBy
        self.images = images
    }
}

struct ParsedImage: Hashable, Sendable {
    let source: String
    let perceptualHash: String
    let averageHash: String
    let differenceHash: String
    let ocrPreview: String
    let thumbnailBase64: String

    init(
        source: String,
        perceptualHash: String = "",
        averageHash: String,
        differenceHash: String,
        ocrPreview: String,
        thumbnailBase64: String
    ) {
        self.source = source
        self.perceptualHash = perceptualHash.isEmpty ? averageHash : perceptualHash
        self.averageHash = averageHash
        self.differenceHash = differenceHash
        self.ocrPreview = ocrPreview
        self.thumbnailBase64 = thumbnailBase64
    }
}

struct SuspiciousPair: Hashable, Sendable {
    let fileA: String
    let fileB: String
    let score: Double
    let evidence: String
    let detailLines: [String]
    let attachments: [ReportAttachment]

    init(
        fileA: String,
        fileB: String,
        score: Double,
        evidence: String,
        detailLines: [String] = [],
        attachments: [ReportAttachment] = []
    ) {
        self.fileA = fileA
        self.fileB = fileB
        self.score = score
        self.evidence = evidence
        self.detailLines = detailLines
        self.attachments = attachments
    }
}

struct MetadataCollision: Hashable, Sendable {
    let author: String
    let files: [String]
}

struct CrossBatchMatch: Hashable, Sendable {
    let currentFile: String
    let previousFile: String
    let previousScan: String
    let distance: Int
    let status: String
}

struct ReportAssembler {
    func assemble(
        title: String,
        sourceURL: URL,
        scanDirectory: String,
        textPairs: [SuspiciousPair],
        codePairs: [SuspiciousPair],
        imagePairs: [SuspiciousPair],
        metadataCollisions: [MetadataCollision],
        dedupPairs: [SuspiciousPair],
        fingerprints: [FingerprintRecord],
        crossBatch: [CrossBatchMatch]
    ) -> AuditReport {
        let overviewRows = buildOverviewRows(
            textPairs: textPairs,
            codePairs: codePairs,
            imagePairs: imagePairs,
            metadataCollisions: metadataCollisions,
            dedupPairs: dedupPairs,
            crossBatch: crossBatch
        )

        let metrics = [
            ReportMetric(title: "文本/代码高危相似", value: "\(textPairs.count + codePairs.count)", systemImage: "exclamationmark.triangle.fill"),
            ReportMetric(title: "图片雷同组合", value: "\(imagePairs.count)", systemImage: "photo.fill.on.rectangle.fill"),
            ReportMetric(title: "元数据碰撞", value: "\(metadataCollisions.count)", systemImage: "person.crop.rectangle"),
        ]

        let sections = [
            ReportSection(
                kind: .overview,
                title: "事态总览",
                summary: "原生报告中心已经接管审计结果展示。这里汇总高危相似、图片复用、元数据碰撞和跨批次复用情况。",
                callouts: [
                    "文本高危相似：\(textPairs.count) 对",
                    "代码结构相似：\(codePairs.count) 对",
                    "图片雷同组合：\(imagePairs.count) 组",
                    "跨批次复用：\(crossBatch.count) 条"
                ],
                table: ReportTable(
                    headers: ["对象 A", "对象 B", "关联次数", "关联类型"],
                    rows: overviewRows
                )
            ),
            ReportSection(
                kind: .text,
                title: "文本内容相似度分析",
                summary: "基于原生 TF-IDF + cosine 的文本相似度分析。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: textPairs.map {
                        ReportTableRow(
                            columns: [$0.fileA, $0.fileB, String(format: "%.2f%%", $0.score * 100), $0.evidence],
                            detailTitle: "\($0.fileA) ↔ \($0.fileB)",
                            detailBody: detailBody(for: $0, label: "文本相似度"),
                            badges: [severityBadge(for: $0.score)],
                            attachments: $0.attachments
                        )
                    }
                )
            ),
            ReportSection(
                kind: .code,
                title: "代码/脚本抄袭分析",
                summary: "提取 fenced code 与启发式代码片段，按 token shingles 和结构 token 做比对。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: codePairs.map {
                        ReportTableRow(
                            columns: [$0.fileA, $0.fileB, String(format: "%.2f%%", $0.score * 100), $0.evidence],
                            detailTitle: "\($0.fileA) ↔ \($0.fileB)",
                            detailBody: detailBody(for: $0, label: "代码结构相似度"),
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "代码", tone: .accent)],
                            attachments: $0.attachments
                        )
                    }
                )
            ),
            ReportSection(
                kind: .image,
                title: "图片证据详列",
                summary: "当前版本支持 DOCX 嵌入媒体与 PDF 内嵌图片提取，页级缩略图只在无法解析图片流时兜底。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: imagePairs.map {
                        ReportTableRow(
                            columns: [$0.fileA, $0.fileB, String(format: "%.2f%%", $0.score * 100), $0.evidence],
                            detailTitle: "\($0.fileA) ↔ \($0.fileB)",
                            detailBody: detailBody(for: $0, label: "图片相似度"),
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "图片", tone: .warning)],
                            attachments: $0.attachments
                        )
                    }
                )
            ),
            ReportSection(
                kind: .metadata,
                title: "元数据碰撞",
                summary: "按作者等元数据字段聚合可能存在的交叉来源。",
                table: ReportTable(
                    headers: ["作者", "涉及文件数", "文件列表"],
                    rows: metadataCollisions.map {
                        ReportTableRow(
                            columns: [$0.author, "\($0.files.count)", $0.files.joined(separator: " | ")],
                            detailTitle: $0.author,
                            detailBody: "涉及文件：\n\($0.files.joined(separator: "\n"))",
                            badges: [ReportBadge(title: "元数据", tone: .neutral)]
                        )
                    }
                )
            ),
            ReportSection(
                kind: .dedup,
                title: "重复文件去重报告",
                summary: "按更严格阈值列出疑似重复或高度改写的文件对。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: dedupPairs.map {
                        ReportTableRow(
                            columns: [$0.fileA, $0.fileB, String(format: "%.2f%%", $0.score * 100), $0.evidence],
                            detailTitle: "\($0.fileA) ↔ \($0.fileB)",
                            detailBody: detailBody(for: $0, label: "重复检测相似度"),
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "重复", tone: .warning)],
                            attachments: $0.attachments
                        )
                    }
                )
            ),
            ReportSection(
                kind: .fingerprints,
                title: "文件指纹数据库",
                summary: "当前批次生成的原生指纹记录。",
                table: ReportTable(
                    headers: ["文件名", "作者", "扩展名", "SimHash"],
                    rows: fingerprints.map {
                        ReportTableRow(
                            columns: [$0.filename, $0.author, $0.ext, $0.simhash],
                            detailTitle: $0.filename,
                            detailBody: "作者：\($0.author)\n扩展名：\($0.ext)\n字符数：\($0.size)\nSimHash：\($0.simhash)",
                            badges: [ReportBadge(title: $0.ext.uppercased(), tone: .accent)]
                        )
                    }
                )
            ),
            ReportSection(
                kind: .crossBatch,
                title: "二次审计（跨批次复用）",
                summary: "当前批次与历史指纹库的近似匹配结果。",
                table: ReportTable(
                    headers: ["当前文件", "历史文件", "批次", "位差", "状态"],
                    rows: crossBatch.map {
                        ReportTableRow(
                            columns: [$0.currentFile, $0.previousFile, $0.previousScan, "\($0.distance)", $0.status],
                            detailTitle: "\($0.currentFile) ↔ \($0.previousFile)",
                            detailBody: "历史批次：\($0.previousScan)\nSimHash 位差：\($0.distance)\n状态：\($0.status)",
                            badges: [ReportBadge(title: $0.status, tone: $0.status == "疑似复用" ? .danger : .success)]
                        )
                    }
                )
            ),
        ]

        return AuditReport(
            title: title,
            sourcePath: sourceURL.path,
            scanDirectoryPath: scanDirectory,
            metrics: metrics,
            sections: sections
        )
    }

    private func severityBadge(for score: Double) -> ReportBadge {
        if score >= 0.90 {
            return ReportBadge(title: "高危", tone: .danger)
        }
        if score >= 0.75 {
            return ReportBadge(title: "关注", tone: .warning)
        }
        return ReportBadge(title: "一般", tone: .neutral)
    }

    private func detailBody(for pair: SuspiciousPair, label: String) -> String {
        var parts = ["\(label)：\(String(format: "%.2f%%", pair.score * 100))"]
        if !pair.detailLines.isEmpty {
            parts.append(pair.detailLines.joined(separator: "\n"))
        }
        parts.append("证据：\(pair.evidence)")
        return parts.joined(separator: "\n\n")
    }

    private func buildOverviewRows(
        textPairs: [SuspiciousPair],
        codePairs: [SuspiciousPair],
        imagePairs: [SuspiciousPair],
        metadataCollisions: [MetadataCollision],
        dedupPairs: [SuspiciousPair],
        crossBatch: [CrossBatchMatch]
    ) -> [ReportTableRow] {
        struct Association {
            var count = 0
            var reasons: [String: Int] = [:]
        }

        func pairKey(_ left: String, _ right: String) -> String {
            [left, right].sorted().joined(separator: "|||")
        }

        var map: [String: Association] = [:]

        func add(_ left: String, _ right: String, reason: String) {
            let key = pairKey(left, right)
            var assoc = map[key, default: Association()]
            assoc.count += 1
            assoc.reasons[reason, default: 0] += 1
            map[key] = assoc
        }

        for item in textPairs where item.score >= 0.85 {
            add(item.fileA, item.fileB, reason: "文本")
        }
        for item in codePairs where item.score >= 0.75 {
            add(item.fileA, item.fileB, reason: "代码")
        }
        for item in imagePairs where item.score >= 0.60 {
            add(item.fileA, item.fileB, reason: "图片")
        }
        for item in dedupPairs where item.score >= 0.90 {
            add(item.fileA, item.fileB, reason: "重复")
        }
        for item in crossBatch where item.distance <= 2 {
            add(item.currentFile, item.previousFile, reason: "跨批次")
        }
        for item in metadataCollisions {
            guard item.files.count > 1 else { continue }
            for left in item.files.indices {
                for right in item.files.indices where right > left {
                    add(item.files[left], item.files[right], reason: "元数据")
                }
            }
        }

        return map
            .map { key, value in
                let pair = key.components(separatedBy: "|||")
                let reasons = value.reasons.keys.sorted().joined(separator: " / ")
                return ReportTableRow(
                    columns: [pair.first ?? "", pair.dropFirst().first ?? "", "\(value.count)", reasons],
                    detailTitle: "\(pair.first ?? "") ↔ \(pair.dropFirst().first ?? "")",
                    detailBody: "关联次数：\(value.count)\n关联类型：\(reasons)",
                    badges: [
                        ReportBadge(title: value.count >= 3 ? "强关联" : "关联", tone: value.count >= 3 ? .danger : .warning),
                        ReportBadge(title: reasons, tone: .accent),
                    ]
                )
            }
            .sorted {
                let lhs = Int($0.columns[2]) ?? 0
                let rhs = Int($1.columns[2]) ?? 0
                return lhs > rhs
            }
    }
}

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

private final class PDFEmbeddedImageExtractor {
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

struct TextSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...5, charNGramRange: 3...7, wordWeight: 0.6, charWeight: 0.4)
        var pairs: [SuspiciousPair] = []

        for left in documents.indices {
            for right in documents.indices where right > left {
                let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
                if score >= threshold {
                    let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
                    pairs.append(
                        SuspiciousPair(
                            fileA: documents[left].filename,
                            fileB: documents[right].filename,
                            score: score,
                            evidence: evidence.summary,
                            detailLines: [
                                "文本相似度：\(String(format: "%.2f%%", score * 100))",
                                "最长公共片段：\(evidence.longestCommonLength)",
                                "AI 洗稿标记：\(score >= threshold && evidence.longestCommonLength < 20 ? "是" : "否")"
                            ],
                            attachments: [
                                ReportAttachment(title: documents[left].filename, subtitle: "上下文 A", body: evidence.leftContext, imageBase64: nil),
                                ReportAttachment(title: documents[right].filename, subtitle: "上下文 B", body: evidence.rightContext, imageBase64: nil)
                            ]
                        )
                    )
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct DedupAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText), wordNGramRange: 1...3, charNGramRange: 3...5, wordWeight: 0.5, charWeight: 0.5)
        var pairs: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
                let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
                guard score >= threshold else { continue }
                let evidence = TextEvidenceBuilder.build(left: documents[left].content, right: documents[right].content)
                pairs.append(
                    SuspiciousPair(
                        fileA: documents[left].filename,
                        fileB: documents[right].filename,
                        score: score,
                        evidence: evidence.summary,
                        detailLines: ["重复检测相似度：\(String(format: "%.2f%%", score * 100))", "最长公共片段：\(evidence.longestCommonLength)"],
                        attachments: [
                            ReportAttachment(title: documents[left].filename, subtitle: "重复上下文 A", body: evidence.leftContext, imageBase64: nil),
                            ReportAttachment(title: documents[right].filename, subtitle: "重复上下文 B", body: evidence.rightContext, imageBase64: nil)
                        ]
                    )
                )
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct CodeSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        var results: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
                let lhsBlocks = CodeBlockExtractor.candidates(from: documents[left].codeBlocks)
                let rhsBlocks = CodeBlockExtractor.candidates(from: documents[right].codeBlocks)
                guard !lhsBlocks.isEmpty, !rhsBlocks.isEmpty else { continue }

                guard let bestMatch = bestMatch(left: lhsBlocks, right: rhsBlocks) else {
                    continue
                }

                if bestMatch.score >= 0.60 {
                    let detailLines = [
                        "词元相似度：\(String(format: "%.2f%%", bestMatch.lexicalScore * 100))",
                        "结构相似度：\(String(format: "%.2f%%", bestMatch.structuralScore * 100))",
                        "共享标记数：\(bestMatch.sharedTokenCount)",
                        "共享覆盖率：\(String(format: "%.2f%%", bestMatch.sharedTokenRatio * 100))",
                        "命中片段：\(bestMatch.left.label) ↔ \(bestMatch.right.label)"
                    ]
                    results.append(
                        SuspiciousPair(
                            fileA: documents[left].filename,
                            fileB: documents[right].filename,
                            score: bestMatch.score,
                            evidence: bestMatch.summary,
                            detailLines: detailLines,
                            attachments: [
                                ReportAttachment(
                                    title: documents[left].filename,
                                    subtitle: bestMatch.left.label,
                                    body: bestMatch.left.preview,
                                    imageBase64: nil
                                ),
                                ReportAttachment(
                                    title: documents[right].filename,
                                    subtitle: bestMatch.right.label,
                                    body: bestMatch.right.preview,
                                    imageBase64: nil
                                ),
                                ReportAttachment(
                                    title: "评分细节",
                                    subtitle: "词元 / 结构 / 共享标记",
                                    body: detailLines.joined(separator: "\n"),
                                    imageBase64: nil
                                ),
                            ]
                        )
                    )
                }
            }
        }
        return results.sorted(by: { $0.score > $1.score })
    }

    private func bestMatch(left: [CodeBlockCandidate], right: [CodeBlockCandidate]) -> CodeMatch? {
        var best: CodeMatch?

        for lhs in left {
            for rhs in right {
                let lexicalScore = JaccardSimilarity.score(
                    left: lhs.lexicalSignature,
                    right: rhs.lexicalSignature,
                    shingleSize: 5
                )
                let structuralScore = JaccardSimilarity.score(
                    left: lhs.structuralSignature,
                    right: rhs.structuralSignature,
                    shingleSize: 4
                )
                let lhsTokenSet = Set(lhs.lexicalTokens)
                let rhsTokenSet = Set(rhs.lexicalTokens)
                let sharedTokenCount = lhsTokenSet.intersection(rhsTokenSet).count
                let sharedTokenRatio = Double(sharedTokenCount) / Double(max(lhsTokenSet.union(rhsTokenSet).count, 1))
                let combinedScore = min(1.0, (0.40 * lexicalScore) + (0.40 * structuralScore) + (0.20 * sharedTokenRatio))
                let summary = [
                    "片段 \(lhs.label) ↔ \(rhs.label)",
                    "共享标记 \(sharedTokenCount)",
                    lhs.preview
                ].joined(separator: " | ")
                let candidate = CodeMatch(
                    score: combinedScore,
                    lexicalScore: lexicalScore,
                    structuralScore: structuralScore,
                    sharedTokenCount: sharedTokenCount,
                    sharedTokenRatio: sharedTokenRatio,
                    summary: summary,
                    left: lhs,
                    right: rhs
                )
                if let currentBest = best {
                    if candidate.score > currentBest.score {
                        best = candidate
                    }
                } else {
                    best = candidate
                }
            }
        }

        return best
    }
}

struct ImageReuseAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Int) -> [SuspiciousPair] {
        var pairs: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
                let leftImages = documents[left].images
                let rightImages = documents[right].images
                guard !leftImages.isEmpty, !rightImages.isEmpty else { continue }

                var examples: [(distance: Int, lhs: ParsedImage, rhs: ParsedImage)] = []
                for lhs in leftImages {
                    for rhs in rightImages {
                        let distance = HashDistance.hamming(lhs.perceptualHash, rhs.perceptualHash)
                            + HashDistance.hamming(lhs.averageHash, rhs.averageHash)
                            + HashDistance.hamming(lhs.differenceHash, rhs.differenceHash)
                        if distance <= threshold * 3 {
                            examples.append((distance, lhs, rhs))
                        }
                    }
                }
                if examples.isEmpty == false {
                    let sortedExamples = examples.sorted(by: { $0.distance < $1.distance })
                    let first = sortedExamples[0]
                    let bestDistance = first.distance
                    let normalized = 1.0 - (Double(bestDistance) / Double(max(threshold * 3, 1)))
                    var attachments: [ReportAttachment] = []
                    for (index, example) in sortedExamples.prefix(5).enumerated() {
                        attachments.append(ReportAttachment(
                            title: "\(documents[left].filename) 示例 \(index + 1)",
                            subtitle: example.lhs.source,
                            body: example.lhs.ocrPreview.isEmpty ? "未提取到 OCR 预览" : example.lhs.ocrPreview,
                            imageBase64: example.lhs.thumbnailBase64.isEmpty ? nil : example.lhs.thumbnailBase64
                        ))
                        attachments.append(ReportAttachment(
                            title: "\(documents[right].filename) 示例 \(index + 1)",
                            subtitle: example.rhs.source,
                            body: example.rhs.ocrPreview.isEmpty ? "未提取到 OCR 预览" : example.rhs.ocrPreview,
                            imageBase64: example.rhs.thumbnailBase64.isEmpty ? nil : example.rhs.thumbnailBase64
                        ))
                    }
                    pairs.append(
                        SuspiciousPair(
                            fileA: documents[left].filename,
                            fileB: documents[right].filename,
                            score: max(0.0, normalized),
                            evidence: ["命中图片数：\(examples.count)", first.lhs.source, first.rhs.source, first.lhs.ocrPreview, first.rhs.ocrPreview].filter { !$0.isEmpty }.joined(separator: " | "),
                            detailLines: [
                                "命中图片数：\(examples.count)",
                                "pHash 位差：\(HashDistance.hamming(first.lhs.perceptualHash, first.rhs.perceptualHash))",
                                "aHash 位差：\(HashDistance.hamming(first.lhs.averageHash, first.rhs.averageHash))",
                                "dHash 位差：\(HashDistance.hamming(first.lhs.differenceHash, first.rhs.differenceHash))",
                                "最佳总位差：\(bestDistance)"
                            ],
                            attachments: attachments
                        )
                    )
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct MetadataCollisionAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [MetadataCollision] {
        Dictionary(grouping: documents.compactMap { document -> (String, String)? in
            let candidates = [document.author, document.lastModifiedBy]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let author = candidates.first else { return nil }
            let ignored = ["administrator", "admin", "user", "microsoft office user"]
            guard ignored.contains(author.lowercased()) == false else { return nil }
            return (author, document.filename)
        }, by: { $0.0 })
            .filter { $0.value.count > 1 }
            .map { MetadataCollision(author: $0.key, files: $0.value.map(\.1).sorted()) }
            .sorted(by: { $0.files.count > $1.files.count })
    }
}

struct FingerprintAnalyzer {
    func buildRecords(documents: [ParsedDocument], scanDirectory: String) -> [FingerprintRecord] {
        documents.map { document in
            FingerprintRecord(
                filename: document.filename,
                ext: document.ext,
                author: document.author,
                size: document.cleanText.count,
                simhash: SimHasher.hexHash(for: document.cleanText),
                scanDir: scanDirectory
            )
        }
    }
}

struct CrossBatchReuseAnalyzer {
    func analyze(
        current: [FingerprintRecord],
        historical: [FingerprintRecord],
        whitelistRules: [WhitelistRule],
        whitelistMode: AuditConfiguration.WhitelistMode,
        threshold: Int
    ) -> [CrossBatchMatch] {
        var matches: [CrossBatchMatch] = []
        for record in current {
            for previous in historical {
                let distance = HashDistance.hamming(record.simhash, previous.simhash)
                guard distance <= threshold else { continue }

                let status = whitelistStatus(record: record, previous: previous, rules: whitelistRules)
                if whitelistMode == .hide, status != "疑似复用" {
                    continue
                }
                matches.append(
                    CrossBatchMatch(
                        currentFile: record.filename,
                        previousFile: previous.filename,
                        previousScan: previous.scanDir,
                        distance: distance,
                        status: status
                    )
                )
            }
        }
        return matches.sorted(by: { $0.distance < $1.distance })
    }

    private func whitelistStatus(record: FingerprintRecord, previous: FingerprintRecord, rules: [WhitelistRule]) -> String {
        for rule in rules {
            switch rule.type {
            case .author where !record.author.isEmpty && record.author == rule.pattern:
                return "白名单(author)"
            case .filename where record.filename == rule.pattern || previous.filename == rule.pattern:
                return "白名单(filename)"
            case .simhash where record.simhash == rule.pattern || previous.simhash == rule.pattern:
                return "白名单(simhash)"
            default:
                continue
            }
        }
        return "疑似复用"
    }
}

private enum XMLTextExtractor {
    static func plainText(from data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8) else { return "" }
        let text = xml.replacingOccurrences(of: #"</w:p>"#, with: "\n", options: .regularExpression)
        let withoutTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return withoutTags.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func metadataValue(named tag: String, in data: Data) -> String {
        guard let xml = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: "<\(tag)>(.*?)</\(tag)>", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return ""
        }
        return String(xml[range])
    }
}

private enum ImageHashing {
    static func perceptualHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let size = 32
        let lowSize = 8
        let pixels = grayscalePixels(cgImage: cgImage, width: size, height: size)
        guard pixels.count == size * size else {
            return String(repeating: "0", count: 16)
        }
        var coefficients = Array(repeating: CGFloat(0), count: lowSize * lowSize)
        for u in 0..<lowSize {
            for v in 0..<lowSize {
                var sum = CGFloat(0)
                for x in 0..<size {
                    for y in 0..<size {
                        let pixel = pixels[y * size + x]
                        let cosX = cos(((2 * CGFloat(x) + 1) * CGFloat(u) * .pi) / CGFloat(2 * size))
                        let cosY = cos(((2 * CGFloat(y) + 1) * CGFloat(v) * .pi) / CGFloat(2 * size))
                        sum += pixel * cosX * cosY
                    }
                }
                coefficients[u * lowSize + v] = sum
            }
        }
        let acCoefficients = Array(coefficients.dropFirst())
        let median = acCoefficients.sorted()[acCoefficients.count / 2]
        let bits = coefficients.map { $0 >= median ? "1" : "0" }.joined()
        return binaryStringToHex(bits)
    }

    static func averageHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let size = 8
        let pixels = grayscalePixels(cgImage: cgImage, width: size, height: size)
        guard !pixels.isEmpty else {
            return String(repeating: "0", count: 16)
        }
        let average = pixels.reduce(0, +) / CGFloat(pixels.count)
        let bits = pixels.map { $0 >= average ? "1" : "0" }.joined()
        return binaryStringToHex(bits)
    }

    static func differenceHash(for data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return String(repeating: "0", count: 16)
        }
        let pixels = grayscalePixels(cgImage: cgImage, width: 9, height: 8)
        guard !pixels.isEmpty else {
            return String(repeating: "0", count: 16)
        }
        var bits = ""
        for row in 0..<8 {
            for col in 0..<8 {
                let left = pixels[row * 9 + col]
                let right = pixels[row * 9 + col + 1]
                bits.append(left > right ? "1" : "0")
            }
        }
        return binaryStringToHex(bits)
    }

    static func thumbnailBase64(for data: Data) -> String {
        guard let image = NSImage(data: data),
              let resized = resizedJPEGData(from: image, maxSide: 280) else {
            return ""
        }
        return resized.base64EncodedString()
    }

    static func encodedImageData(for cgImage: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func grayscalePixels(cgImage: CGImage, width: Int, height: Int) -> [CGFloat] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var raw = Array(repeating: UInt8(0), count: width * height)
        guard let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return []
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return raw.map { CGFloat($0) }
    }

    private static func binaryStringToHex(_ bits: String) -> String {
        let value = UInt64(bits, radix: 2) ?? 0
        return String(format: "%016llx", value)
    }

    private static func resizedJPEGData(from image: NSImage, maxSide: CGFloat) -> Data? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }
        let ratio = min(maxSide / sourceSize.width, maxSide / sourceSize.height, 1)
        let targetSize = CGSize(width: sourceSize.width * ratio, height: sourceSize.height * ratio)
        let result = NSImage(size: targetSize)
        result.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        result.unlockFocus()
        return result.jpegData(compressionQuality: 0.78)
    }
}

private enum ImageOCRService {
    static func previewText(from data: Data) -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            return String(text.prefix(120))
        } catch {
            return ""
        }
    }
}

private extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

private enum CodeBlockExtractor {
    static func extract(from text: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"```(?:\w+)?\s*([\s\S]*?)```"#)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var blocks = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if blocks.isEmpty {
            let lines = text.components(separatedBy: .newlines)
            var current: [String] = []
            for line in lines {
                if line.range(of: #"(def |class |for |while |if |import |curl|bash|sh|gcc|python|let |const )"#, options: .regularExpression) != nil {
                    current.append(line)
                } else if current.count >= 2 {
                    blocks.append(current.joined(separator: "\n"))
                    current.removeAll()
                } else {
                    current.removeAll()
                }
            }
            if current.count >= 2 {
                blocks.append(current.joined(separator: "\n"))
            }
        }
        return blocks.filter { $0.count > 20 }
    }

    static func candidates(from blocks: [String]) -> [CodeBlockCandidate] {
        blocks.enumerated().map { index, block in
            let lexicalTokens = block
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
            return CodeBlockCandidate(
                label: "片段 \(index + 1)",
                rawText: block,
                lexicalSignature: lexicalSignature(for: block),
                lexicalTokens: lexicalTokens,
                structuralSignature: structureSignature(for: block),
                preview: block
                    .components(separatedBy: .newlines)
                    .prefix(10)
                    .joined(separator: "\n")
            )
        }
    }

    private static func lexicalSignature(for text: String) -> String {
        normalizedCodeTokens(
            from: text,
            includePunctuation: false
        ).joined(separator: " ")
    }

    private static func structureSignature(for text: String) -> String {
        normalizedCodeTokens(
            from: text,
            includePunctuation: true
        ).joined(separator: " ")
    }

    private static func normalizedCodeTokens(from text: String, includePunctuation: Bool) -> [String] {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"//[^\n\r]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""[^"]*"|'[^']*'"#, with: " str ", options: .regularExpression)
            .replacingOccurrences(of: #"\b\d+\b"#, with: " num ", options: .regularExpression)

        let pattern = includePunctuation
            ? #"[a-z_][a-z0-9_]*|\{|\}|\(|\)|\[|\]|;|,|\.|=|:|\+|\-|\*|/|<|>"#
            : #"[a-z_][a-z0-9_]*"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        return regex?.matches(in: normalized, range: range).compactMap { match -> String? in
            guard let tokenRange = Range(match.range, in: normalized) else {
                return nil
            }
            let token = String(normalized[tokenRange])
            if codeKeywords.contains(token) {
                return token
            }
            if includePunctuation, punctuationTokens.contains(token) {
                return token
            }
            if token == "str" || token == "num" {
                return token
            }
            return "id"
        } ?? []
    }

    private static let codeKeywords: Set<String> = [
        "if", "else", "for", "while", "switch", "case", "class", "def", "func", "return",
        "import", "from", "try", "catch", "except", "let", "var", "const", "public",
        "private", "static", "struct", "enum", "async", "await", "with", "using"
    ]

    private static let punctuationTokens: Set<String> = [
        "{", "}", "(", ")", "[", "]", ";", ",", ".", "=", ":", "+", "-", "*", "/", "<", ">"
    ]
}

private struct CodeBlockCandidate: Hashable, Sendable {
    let label: String
    let rawText: String
    let lexicalSignature: String
    let lexicalTokens: [String]
    let structuralSignature: String
    let preview: String
}

private struct CodeMatch: Hashable, Sendable {
    let score: Double
    let lexicalScore: Double
    let structuralScore: Double
    let sharedTokenCount: Int
    let sharedTokenRatio: Double
    let summary: String
    let left: CodeBlockCandidate
    let right: CodeBlockCandidate
}

private struct TextEvidence: Hashable, Sendable {
    let summary: String
    let leftContext: String
    let rightContext: String
    let longestCommonLength: Int
}

private enum TextEvidenceBuilder {
    static func build(left: String, right: String) -> TextEvidence {
        let match = longestCommonSubstring(left: left, right: right)
        if match.length > 20 {
            let summary = String(left[match.leftRange]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return TextEvidence(
                summary: String(summary.prefix(160)) + (summary.count > 160 ? "..." : ""),
                leftContext: context(in: left, range: match.leftRange),
                rightContext: context(in: right, range: match.rightRange),
                longestCommonLength: match.length
            )
        }
        let leftTerms = Set(terms(in: left))
        let rightTerms = Set(terms(in: right))
        let commonTerms = leftTerms
            .intersection(rightTerms)
            .sorted { $0.count > $1.count }
            .prefix(10)
            .joined(separator: " ")
        let summary = commonTerms.isEmpty ? "全文语义高度相似，未发现显著连续长句（可能是洗稿）" : commonTerms
        return TextEvidence(summary: summary, leftContext: "", rightContext: "", longestCommonLength: match.length)
    }

    private static func context(in text: String, range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -min(120, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let trailing = text.distance(from: range.upperBound, to: text.endIndex)
        let end = text.index(range.upperBound, offsetBy: min(120, trailing), limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func terms(in text: String) -> [String] {
        text.lowercased().split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init)
    }

    private static func longestCommonSubstring(left: String, right: String) -> (leftRange: Range<String.Index>, rightRange: Range<String.Index>, length: Int) {
        let leftChars = Array(left)
        let rightChars = Array(right)
        guard !leftChars.isEmpty, !rightChars.isEmpty else {
            return (left.startIndex..<left.startIndex, right.startIndex..<right.startIndex, 0)
        }
        var previous = Array(repeating: 0, count: rightChars.count + 1)
        var bestLength = 0
        var bestLeftEnd = 0
        var bestRightEnd = 0
        for leftIndex in 1...leftChars.count {
            var current = Array(repeating: 0, count: rightChars.count + 1)
            for rightIndex in 1...rightChars.count {
                if leftChars[leftIndex - 1] == rightChars[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1] + 1
                    if current[rightIndex] > bestLength {
                        bestLength = current[rightIndex]
                        bestLeftEnd = leftIndex
                        bestRightEnd = rightIndex
                    }
                }
            }
            previous = current
        }
        let leftStart = left.index(left.startIndex, offsetBy: bestLeftEnd - bestLength)
        let leftEnd = left.index(left.startIndex, offsetBy: bestLeftEnd)
        let rightStart = right.index(right.startIndex, offsetBy: bestRightEnd - bestLength)
        let rightEnd = right.index(right.startIndex, offsetBy: bestRightEnd)
        return (leftStart..<leftEnd, rightStart..<rightEnd, bestLength)
    }
}

private enum TextNormalizer {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(flag|ctf|cyber|key)\{.*?\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[a-fA-F0-9]{32,}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[a-zA-Z0-9+/]{50,}={0,2}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w\s\u4e00-\u9fa5]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TFIDFVectorizer {
    let wordVectors: [[String: Double]]
    let charVectors: [[String: Double]]
    let wordWeight: Double
    let charWeight: Double

    init(documents: [String], wordNGramRange: ClosedRange<Int> = 1...1, charNGramRange: ClosedRange<Int> = 3...5, wordWeight: Double = 0.6, charWeight: Double = 0.4) {
        self.wordVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: wordNGramRange, tokenizeWords: true)
        self.charVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: charNGramRange, tokenizeWords: false)
        self.wordWeight = wordWeight
        self.charWeight = charWeight
    }

    func combinedCosineSimilarity(left: Int, right: Int) -> Double {
        let word = cosine(lhs: wordVectors[left], rhs: wordVectors[right])
        let char = cosine(lhs: charVectors[left], rhs: charVectors[right])
        return (wordWeight * word) + (charWeight * char)
    }

    private func cosine(lhs: [String: Double], rhs: [String: Double]) -> Double {
        let keys = Set(lhs.keys).union(rhs.keys)
        let dot = keys.reduce(0.0) { $0 + ((lhs[$1] ?? 0) * (rhs[$1] ?? 0)) }
        let lhsNorm = sqrt(lhs.values.reduce(0.0) { $0 + ($1 * $1) })
        let rhsNorm = sqrt(rhs.values.reduce(0.0) { $0 + ($1 * $1) })
        guard lhsNorm > 0, rhsNorm > 0 else { return 0 }
        return dot / (lhsNorm * rhsNorm)
    }

    private static func buildVectors(for documents: [String], ngramRange: ClosedRange<Int>, tokenizeWords: Bool) -> [[String: Double]] {
        let tokenized = documents.map { doc in
            tokenizeWords ? wordNGrams(in: doc, range: ngramRange) : charNGrams(in: doc, range: ngramRange)
        }
        let docCount = Double(max(documents.count, 1))
        var documentFrequency: [String: Double] = [:]
        for tokens in tokenized {
            for token in Set(tokens) {
                documentFrequency[token, default: 0] += 1
            }
        }

        return tokenized.map { tokens in
            let grouped = Dictionary(grouping: tokens, by: { $0 })
            let counts = grouped.mapValues(\.count)
            let total = Double(max(tokens.count, 1))
            var vector: [String: Double] = [:]
            for (token, count) in counts {
                let tf = Double(count) / total
                let idf = log((docCount + 1) / ((documentFrequency[token] ?? 0) + 1)) + 1
                vector[token] = tf * idf
            }
            return vector
        }
    }

    private static func tokenizeWordsIn(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if token.count > 1 {
                result.append(token)
            }
            return true
        }
        return result
    }

    private static func wordNGrams(in text: String, range: ClosedRange<Int>) -> [String] {
        let words = tokenizeWordsIn(text)
        guard words.count >= range.lowerBound else { return [] }
        var grams: [String] = []
        for n in range {
            guard words.count >= n else { continue }
            for index in 0...(words.count - n) {
                grams.append(words[index..<(index + n)].joined(separator: " "))
            }
        }
        return grams
    }

    private static func charNGrams(in text: String, range: ClosedRange<Int>) -> [String] {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        let chars = Array(cleaned)
        guard chars.count >= range.lowerBound else { return [] }
        var grams: [String] = []
        for n in range {
            guard chars.count >= n else { continue }
            for idx in 0...(chars.count - n) {
                grams.append(String(chars[idx..<(idx + n)]))
            }
        }
        return grams
    }
}

private enum JaccardSimilarity {
    static func score(left: String, right: String, shingleSize: Int) -> Double {
        let lhs = shingles(in: left, size: shingleSize)
        let rhs = shingles(in: right, size: shingleSize)
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }

    private static func shingles(in text: String, size: Int) -> Set<String> {
        guard text.count >= size else { return [] }
        let chars = Array(text)
        return Set((0...(chars.count - size)).map { idx in
            String(chars[idx..<(idx + size)])
        })
    }
}

private enum SimHasher {
    static func hexHash(for text: String) -> String {
        let tokens = text.split(separator: " ").map(String.init)
        var weights = Array(repeating: 0, count: 64)
        for token in tokens {
            let hash = stableHash(token)
            for bit in 0..<64 {
                if (hash >> bit) & 1 == 1 {
                    weights[bit] += 1
                } else {
                    weights[bit] -= 1
                }
            }
        }
        var result: UInt64 = 0
        for bit in 0..<64 where weights[bit] > 0 {
            result |= (1 << bit)
        }
        return String(format: "%016llx", result)
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

private enum HashDistance {
    static func hamming(_ left: String, _ right: String) -> Int {
        guard let lhs = UInt64(left, radix: 16), let rhs = UInt64(right, radix: 16) else { return 64 }
        return (lhs ^ rhs).nonzeroBitCount
    }
}

private extension DateFormatter {
    static let pitcherPlantFileName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
