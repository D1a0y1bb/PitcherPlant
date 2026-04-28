import AppKit
import CoreText
import Foundation
import ZIPFoundation

enum ReportExporter {
    static func htmlString(from report: AuditReport) -> String {
        """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>\(escaped(report.title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; color: #18212b; }
            h1 { margin-bottom: 8px; }
            h2 { margin-top: 28px; }
            .metrics { display: flex; gap: 16px; margin: 20px 0 28px; flex-wrap: wrap; }
            .metric { padding: 16px; border-radius: 12px; background: #eef2f5; min-width: 180px; }
            table { width: 100%; border-collapse: collapse; margin-top: 12px; }
            th, td { border: 1px solid #dde3e8; padding: 10px; text-align: left; vertical-align: top; font-size: 13px; }
            th { background: #f7f9fb; }
            .callout { margin: 6px 0; color: #46525f; }
            .detail { margin-top: 8px; padding: 10px; border-radius: 8px; background: #f8fafc; white-space: pre-wrap; }
            .badge { display: inline-block; margin: 0 4px 4px 0; padding: 2px 8px; border-radius: 999px; background: #e8eef5; color: #334155; font-size: 12px; }
            .attachment { margin-top: 8px; padding: 10px; border: 1px solid #e2e8f0; border-radius: 8px; }
            .attachment img { max-width: 220px; display: block; margin-top: 8px; border: 1px solid #e2e8f0; }
          </style>
        </head>
        <body>
          <h1>\(escaped(report.title))</h1>
          <div>生成时间：\(report.createdAt.formatted(date: .abbreviated, time: .standard))</div>
          <div class="metrics">
            \(report.metrics.map { "<div class=\"metric\"><strong>\(escaped($0.title))</strong><div>\(escaped($0.value))</div></div>" }.joined())
          </div>
          \(report.sections.map(renderSection).joined())
        </body>
        </html>
        """
    }

    static func exportHTML(report: AuditReport, to url: URL) throws {
        try htmlString(from: report).write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportPDF(report: AuditReport, to url: URL) throws {
        let data = try pdfData(from: report)
        try data.write(to: url)
    }

    @MainActor
    private static func pdfData(from report: AuditReport) throws -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 48
        let contentRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let text = ReportTextFormatter.string(from: report)
        let font = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                kCTFontAttributeName as NSAttributedString.Key: font,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.1, alpha: 1),
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(
                domain: "PitcherPlant.ReportExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "PDF 上下文创建失败"]
            )
        }

        var range = CFRange(location: 0, length: 0)
        repeat {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            let path = CGPath(rect: contentRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            context.restoreGState()
            context.endPDFPage()
            guard visibleRange.length > 0 else {
                break
            }
            range.location += visibleRange.length
        } while range.location < attributed.length
        context.closePDF()
        return data as Data
    }

    static func exportCSV(report: AuditReport, to url: URL) throws {
        var rows: [[String]] = [[
            "section",
            "evidence_id",
            "type",
            "object_a",
            "object_b",
            "score",
            "cross_batch_batch",
            "cross_batch_distance",
            "cross_batch_status",
            "decision",
            "risk",
            "whitelist_status",
            "whitelist_rule",
            "source_references",
            "detail"
        ]]
        for section in report.sections {
            for row in section.table?.rows ?? [] {
                let crossBatchFields = crossBatchCSVFields(for: row, in: section)
                rows.append([
                    section.title,
                    row.evidenceID?.uuidString ?? row.id.uuidString,
                    row.evidenceType?.rawValue ?? section.kind.rawValue,
                    row.columns[safe: 0] ?? "",
                    row.columns[safe: 1] ?? "",
                    scoreCSVValue(for: row, in: section),
                    crossBatchFields.batch,
                    crossBatchFields.distance,
                    crossBatchFields.status,
                    row.review?.decision.rawValue ?? EvidenceDecision.pending.rawValue,
                    row.riskAssessment?.level.rawValue ?? "",
                    row.whitelistStatus?.status.rawValue ?? "",
                    row.whitelistStatus?.matchedRuleType?.rawValue ?? "",
                    row.attachments.map(\.sourceReferenceText).joined(separator: " | "),
                    row.detailBody,
                ])
            }
        }
        let csv = rows.map { row in
            row.map(csvEscaped).joined(separator: ",")
        }.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func scoreCSVValue(for row: ReportTableRow, in section: ReportSection) -> String {
        if section.kind == .crossBatch || row.evidenceType == .crossBatch {
            if let assessment = row.riskAssessment {
                return "\(assessment.formattedScore)%"
            }
            return ""
        }
        return row.columns[safe: 2] ?? row.riskAssessment.map { "\($0.formattedScore)%" } ?? ""
    }

    private static func crossBatchCSVFields(for row: ReportTableRow, in section: ReportSection) -> (batch: String, distance: String, status: String) {
        guard section.kind == .crossBatch || row.evidenceType == .crossBatch else {
            return ("", "", "")
        }
        let metadata = row.metadata ?? [:]
        return (
            metadata[CrossBatchGraphMetadataKey.batchName] ?? row.columns[safe: 2] ?? "",
            metadata[CrossBatchGraphMetadataKey.distance] ?? row.columns[safe: 3] ?? "",
            metadata[CrossBatchGraphMetadataKey.status] ?? row.columns[safe: 4] ?? ""
        )
    }

    static func exportJSON(report: AuditReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    static func exportMarkdown(report: AuditReport, to url: URL) throws {
        try ReportMarkdownFormatter.string(from: report).write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportEvidenceBundle(report: AuditReport, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        try add(Data(htmlString(from: report).utf8), path: "report.html", to: archive)
        try add(Data(ReportMarkdownFormatter.string(from: report).utf8), path: "report.md", to: archive)

        let pdfURL = FileManager.default.temporaryDirectory.appendingPathComponent("PitcherPlant-\(UUID().uuidString).pdf")
        try exportPDF(report: report, to: pdfURL)
        try add(Data(contentsOf: pdfURL), path: "report.pdf", to: archive)
        try? FileManager.default.removeItem(at: pdfURL)

        let csvURL = FileManager.default.temporaryDirectory.appendingPathComponent("PitcherPlant-\(UUID().uuidString).csv")
        try exportCSV(report: report, to: csvURL)
        try add(Data(contentsOf: csvURL), path: "evidence.csv", to: archive)
        try? FileManager.default.removeItem(at: csvURL)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try add(try encoder.encode(report), path: "report.json", to: archive)

        var imageIndex = 1
        for section in report.sections {
            for row in section.table?.rows ?? [] {
                for attachment in row.attachments {
                    guard let base64 = attachment.imageBase64,
                          let data = Data(base64Encoded: base64) else {
                        continue
                    }
                    let safeName = sanitizedPathComponent("\(section.kind.rawValue)-\(row.id.uuidString)-\(imageIndex).jpg")
                    try add(data, path: "attachments/\(safeName)", to: archive)
                    imageIndex += 1
                }
            }
        }
    }

    private static func renderSection(_ section: ReportSection) -> String {
        let callouts: String = section.callouts.map { value -> String in
            "<div class=\"callout\">\(escaped(value))</div>"
        }.joined()
        let tableHTML: String
        if let table = section.table {
            let header: String = table.headers.map { value -> String in
                "<th>\(escaped(value))</th>"
            }.joined()
            let rows: String = table.rows.map { row -> String in
                let badges: String = row.badges.map { badge -> String in
                    "<span class=\"badge\">\(escaped(badge.title))</span>"
                }.joined()
                let whitelist = row.whitelistStatus?.exportSummary ?? ""
                let whitelistHTML = whitelist.isEmpty ? "" : "<div class=\"detail\"><strong>白名单</strong><br>\(escaped(whitelist))</div>"
                let details = "<div class=\"detail\"><strong>\(escaped(row.detailTitle))</strong><br>\(escaped(row.detailBody))</div>\(whitelistHTML)"
                let attachments: String = row.attachments.map { attachment -> String in
                    let image: String = attachment.imageBase64
                        .flatMap(sanitizedImageDataSource)
                        .map { "<img src=\"\($0)\" alt=\"\(escapedAttribute(attachment.title))\" />" } ?? ""
                    return "<div class=\"attachment\"><strong>\(escaped(attachment.title))</strong><div>\(escaped(attachment.sourceReferenceText))</div><div>\(escaped(attachment.body))</div>\(image)</div>"
                }.joined()
                let evidenceCell = "<td>\(badges)\(details)\(attachments)</td>"
                let columns: String = row.columns.map { value -> String in
                    "<td>\(escaped(value))</td>"
                }.joined()
                return "<tr>\(columns)\(evidenceCell)</tr>"
            }.joined()
            tableHTML = "<table><thead><tr>\(header)<th>详情</th></tr></thead><tbody>\(rows)</tbody></table>"
        } else {
            tableHTML = ""
        }
        return """
        <section>
          <h2>\(escaped(section.title))</h2>
          <p>\(escaped(section.summary))</p>
          \(callouts)
          \(tableHTML)
        </section>
        """
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapedAttribute(_ value: String) -> String {
        escaped(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func sanitizedImageDataSource(from base64: String) -> String? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return "data:image/jpeg;base64,\(trimmed)"
    }

    private static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return data.subdata(in: start..<end)
        }
    }

    private static func sanitizedPathComponent(_ value: String) -> String {
        value.replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "_", options: .regularExpression)
    }
}

enum ReportTextFormatter {
    static func string(from report: AuditReport) -> String {
        var lines: [String] = [report.title, "生成时间: \(report.createdAt.formatted(date: .abbreviated, time: .standard))", ""]
        for metric in report.metrics {
            lines.append("\(metric.title): \(metric.value)")
        }
        lines.append("")
        for section in report.sections {
            lines.append("## \(section.title)")
            lines.append(section.summary)
            lines.append(contentsOf: section.callouts.map { "- \($0)" })
            if let table = section.table {
                lines.append(table.headers.joined(separator: " | "))
                for row in table.rows {
                    lines.append(row.columns.joined(separator: " | "))
                    lines.append(row.detailTitle)
                    lines.append(row.detailBody)
                    for attachment in row.attachments {
                        lines.append("附件: \(attachment.title) / \(attachment.sourceReferenceText)")
                        lines.append(attachment.body)
                    }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

enum ReportMarkdownFormatter {
    static func string(from report: AuditReport) -> String {
        var lines: [String] = ["# \(report.title)", "", "生成时间：\(report.createdAt.formatted(date: .abbreviated, time: .standard))", ""]
        for metric in report.metrics {
            lines.append("- \(metric.title)：\(metric.value)")
        }
        lines.append("")

        for section in report.sections {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.summary)
            lines.append("")
            for callout in section.callouts {
                lines.append("- \(callout)")
            }
            if let table = section.table {
                lines.append("")
                lines.append("| \(table.headers.joined(separator: " | ")) | 复核 | 风险 | 白名单 |")
                lines.append("| \(Array(repeating: "---", count: table.headers.count + 3).joined(separator: " | ")) |")
                for row in table.rows {
                    let columns = row.columns.map(markdownCell)
                    let decision = row.review?.decision.title ?? EvidenceDecision.pending.title
                    let risk = row.riskAssessment?.level.title ?? ""
                    let whitelist = markdownCell(row.whitelistStatus?.exportSummary ?? "")
                    lines.append("| \((columns + [decision, risk, whitelist]).joined(separator: " | ")) |")
                    for attachment in row.attachments where attachment.sourceReference != nil {
                        lines.append("")
                        lines.append("- 来源：\(attachment.sourceReferenceText)")
                    }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }
}
