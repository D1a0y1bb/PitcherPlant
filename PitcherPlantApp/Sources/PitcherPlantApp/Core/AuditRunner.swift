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
    let images: [ParsedImage]
}

struct ParsedImage: Hashable, Sendable {
    let source: String
    let averageHash: String
    let differenceHash: String
    let ocrPreview: String
}

struct SuspiciousPair: Hashable, Sendable {
    let fileA: String
    let fileB: String
    let score: Double
    let evidence: String
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
                ]
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
                            detailBody: "文本相似度：\(String(format: "%.2f%%", $0.score * 100))\n\n证据：\($0.evidence)",
                            badges: [severityBadge(for: $0.score)]
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
                            detailBody: "代码结构相似度：\(String(format: "%.2f%%", $0.score * 100))\n\n关键证据：\($0.evidence)",
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "代码", tone: .accent)]
                        )
                    }
                )
            ),
            ReportSection(
                kind: .image,
                title: "图片证据详列",
                summary: "当前版本支持 DOCX 嵌入媒体与 PDF 页面级图片证据的原生 hash 与 OCR 预览。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: imagePairs.map {
                        ReportTableRow(
                            columns: [$0.fileA, $0.fileB, String(format: "%.2f%%", $0.score * 100), $0.evidence],
                            detailTitle: "\($0.fileA) ↔ \($0.fileB)",
                            detailBody: "图片相似度：\(String(format: "%.2f%%", $0.score * 100))\n\n证据：\($0.evidence)",
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "图片", tone: .warning)]
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
                            detailBody: "重复检测相似度：\(String(format: "%.2f%%", $0.score * 100))\n\n证据：\($0.evidence)",
                            badges: [severityBadge(for: $0.score), ReportBadge(title: "重复", tone: .warning)]
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
}

struct DocumentIngestionService {
    let configuration: AuditConfiguration

    func ingestDocuments(in directory: URL) throws -> [ParsedDocument] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var documents: [ParsedDocument] = []

        while let url = enumerator?.nextObject() as? URL {
            guard ["pdf", "docx", "md", "txt"].contains(url.pathExtension.lowercased()) else {
                continue
            }
            if let document = try parseDocument(at: url) {
                documents.append(document)
            }
        }

        return documents
    }

    private func parseDocument(at url: URL) throws -> ParsedDocument? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "txt":
            let content = try String(contentsOf: url, encoding: .utf8)
            return buildDocument(url: url, ext: ext, content: content, author: "", images: [])
        case "pdf":
            guard let document = PDFDocument(url: url) else { return nil }
            let content = document.string ?? ""
            let author = (document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String) ?? ""
            let images = parsePDFImages(document: document)
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
        var images: [ParsedImage] = []

        if let entry = archive["word/document.xml"] {
            var data = Data()
            _ = try archive.extract(entry) { part in
                data.append(part)
            }
            content = XMLTextExtractor.plainText(from: data)
        }

        if let entry = archive["docProps/core.xml"] {
            var data = Data()
            _ = try archive.extract(entry) { part in
                data.append(part)
            }
            author = XMLTextExtractor.metadataValue(named: "dc:creator", in: data)
        }

        for entry in archive where entry.path.hasPrefix("word/media/") {
            var data = Data()
            _ = try archive.extract(entry) { part in
                data.append(part)
            }
            images.append(ParsedImage(
                source: entry.path,
                averageHash: ImageHashing.averageHash(for: data),
                differenceHash: ImageHashing.differenceHash(for: data),
                ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : ""
            ))
        }

        return buildDocument(url: url, ext: "docx", content: content, author: author, images: images)
    }

    private func buildDocument(url: URL, ext: String, content: String, author: String, images: [ParsedImage]) -> ParsedDocument {
        let normalized = content.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedDocument(
            url: url,
            filename: url.lastPathComponent,
            ext: ext,
            content: content,
            cleanText: TextNormalizer.clean(normalized),
            codeBlocks: CodeBlockExtractor.extract(from: content),
            author: author,
            images: images
        )
    }

    private func parsePDFImages(document: PDFDocument) -> [ParsedImage] {
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
                    averageHash: ImageHashing.averageHash(for: data),
                    differenceHash: ImageHashing.differenceHash(for: data),
                    ocrPreview: configuration.useVisionOCR ? ImageOCRService.previewText(from: data) : ""
                )
            )
        }
        return images
    }
}

struct TextSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        let vectorizer = TFIDFVectorizer(documents: documents.map(\.cleanText))
        var pairs: [SuspiciousPair] = []

        for left in documents.indices {
            for right in documents.indices where right > left {
                let score = vectorizer.combinedCosineSimilarity(left: left, right: right)
                if score >= threshold {
                    let evidence = String(documents[left].cleanText.prefix(90))
                    pairs.append(SuspiciousPair(fileA: documents[left].filename, fileB: documents[right].filename, score: score, evidence: evidence))
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct DedupAnalyzer {
    func analyze(documents: [ParsedDocument], threshold: Double) -> [SuspiciousPair] {
        TextSimilarityAnalyzer().analyze(documents: documents, threshold: threshold)
    }
}

struct CodeSimilarityAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [SuspiciousPair] {
        guard documents.count > 1 else { return [] }
        var results: [SuspiciousPair] = []
        for left in documents.indices {
            for right in documents.indices where right > left {
                let lhs = documents[left].codeBlocks.joined(separator: "\n")
                let rhs = documents[right].codeBlocks.joined(separator: "\n")
                guard !lhs.isEmpty, !rhs.isEmpty else { continue }
                let score = JaccardSimilarity.score(
                    left: CodeBlockExtractor.normalize(lhs),
                    right: CodeBlockExtractor.normalize(rhs),
                    shingleSize: 8
                )
                if score >= 0.60 {
                    results.append(
                        SuspiciousPair(
                            fileA: documents[left].filename,
                            fileB: documents[right].filename,
                            score: score,
                            evidence: String(lhs.prefix(120))
                        )
                    )
                }
            }
        }
        return results.sorted(by: { $0.score > $1.score })
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

                var bestDistance = Int.max
                var evidence = ""
                for lhs in leftImages {
                    for rhs in rightImages {
                        let distance = HashDistance.hamming(lhs.averageHash, rhs.averageHash) + HashDistance.hamming(lhs.differenceHash, rhs.differenceHash)
                        if distance < bestDistance {
                            bestDistance = distance
                            evidence = [lhs.source, rhs.source, lhs.ocrPreview, rhs.ocrPreview].filter { !$0.isEmpty }.joined(separator: " | ")
                        }
                    }
                }
                if bestDistance <= threshold * 2 {
                    let normalized = 1.0 - (Double(bestDistance) / Double(max(threshold * 2, 1)))
                    pairs.append(SuspiciousPair(fileA: documents[left].filename, fileB: documents[right].filename, score: max(0.0, normalized), evidence: evidence))
                }
            }
        }
        return pairs.sorted(by: { $0.score > $1.score })
    }
}

struct MetadataCollisionAnalyzer {
    func analyze(documents: [ParsedDocument]) -> [MetadataCollision] {
        Dictionary(grouping: documents.filter { !$0.author.isEmpty }, by: \.author)
            .filter { $0.value.count > 1 }
            .map { MetadataCollision(author: $0.key, files: $0.value.map(\.filename).sorted()) }
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

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }
}

private enum TextNormalizer {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"(flag|ctf|cyber|key)\{.*?\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w\s\u4e00-\u9fa5]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct TFIDFVectorizer {
    let wordVectors: [[String: Double]]
    let charVectors: [[String: Double]]

    init(documents: [String]) {
        self.wordVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: 1...1, tokenizeWords: true)
        self.charVectors = TFIDFVectorizer.buildVectors(for: documents, ngramRange: 3...5, tokenizeWords: false)
    }

    func combinedCosineSimilarity(left: Int, right: Int) -> Double {
        let word = cosine(lhs: wordVectors[left], rhs: wordVectors[right])
        let char = cosine(lhs: charVectors[left], rhs: charVectors[right])
        return (0.6 * word) + (0.4 * char)
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
            tokenizeWords ? tokenizeWordsIn(doc) : charNGrams(in: doc, range: ngramRange)
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
            hash *= 1099511628211
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
