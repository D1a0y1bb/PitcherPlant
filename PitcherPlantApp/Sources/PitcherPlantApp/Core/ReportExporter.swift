import AppKit
import Foundation

enum ReportExporter {
    static func exportHTML(report: AuditReport, to url: URL) throws {
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>\(escaped(report.title))</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 32px; color: #18212b; }
            h1 { margin-bottom: 8px; }
            h2 { margin-top: 28px; }
            .metrics { display: flex; gap: 16px; margin: 20px 0 28px; }
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
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func exportPDF(report: AuditReport, to url: URL) throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 820, height: 1800))
        textView.string = ReportTextFormatter.string(from: report)
        let data = textView.dataWithPDF(inside: textView.bounds)
        try data.write(to: url)
    }

    private static func renderSection(_ section: ReportSection) -> String {
        let callouts = section.callouts.map { "<div class=\"callout\">\(escaped($0))</div>" }.joined()
        let tableHTML: String
        if let table = section.table {
            let header = table.headers.map { "<th>\(escaped($0))</th>" }.joined()
            let rows = table.rows.map { row in
                let badges = row.badges.map { "<span class=\"badge\">\(escaped($0.title))</span>" }.joined()
                let details = "<div class=\"detail\"><strong>\(escaped(row.detailTitle))</strong><br>\(escaped(row.detailBody))</div>"
                let attachments = row.attachments.map { attachment in
                    let image = attachment.imageBase64.map { "<img src=\"data:image/jpeg;base64,\($0)\" alt=\"\(escaped(attachment.title))\" />" } ?? ""
                    return "<div class=\"attachment\"><strong>\(escaped(attachment.title))</strong><div>\(escaped(attachment.subtitle))</div><div>\(escaped(attachment.body))</div>\(image)</div>"
                }.joined()
                let evidenceCell = "<td>\(badges)\(details)\(attachments)</td>"
                return "<tr>\(row.columns.map { "<td>\(escaped($0))</td>" }.joined())\(evidenceCell)</tr>"
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
                        lines.append("附件: \(attachment.title) / \(attachment.subtitle)")
                        lines.append(attachment.body)
                    }
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
