import Foundation
import Testing
@testable import PitcherPlantApp

@Test
func configurationDefaultsBuildPaths() {
    let root = URL(fileURLWithPath: "/tmp/pitcherplant")
    let defaults = AuditConfiguration.defaults(for: root)
    #expect(defaults.directoryPath.contains("/tmp/pitcherplant/date"))
    #expect(defaults.outputDirectoryPath.contains("/tmp/pitcherplant/reports/full"))
}

@Test
func presetStorageRoundTripsByWorkspaceRoot() throws {
    let suiteName = "pitcherplant.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("无法创建测试专用 UserDefaults")
        return
    }
    let root = URL(fileURLWithPath: "/tmp/pitcherplant-presets")
    let configuration = AuditConfiguration.defaults(for: root)

    let saved = AppPreferences.savePreset(named: "常用目录", configuration: configuration, for: root, defaults: defaults)
    #expect(saved.count == 1)
    #expect(saved.first?.name == "常用目录")

    let loaded = AppPreferences.loadPresets(for: root, defaults: defaults)
    #expect(loaded.count == 1)
    #expect(loaded.first?.configuration == configuration)

    let remaining = AppPreferences.deletePreset(id: try #require(loaded.first?.id), for: root, defaults: defaults)
    #expect(remaining.isEmpty)
}

@Test
func reportLibrarySearchMatchesLegacyAndSectionEvidence() {
    let section = ReportSection(
        kind: .code,
        title: "代码/脚本抄袭分析",
        summary: "结构 token 比对",
        table: ReportTable(
            headers: ["文件 A", "文件 B"],
            rows: [
                ReportTableRow(
                    columns: ["alpha.swift", "beta.swift"],
                    detailTitle: "alpha.swift ↔ beta.swift",
                    detailBody: "命中了相同的结构片段",
                    badges: [ReportBadge(title: "高危", tone: .danger)]
                )
            ]
        )
    )
    let nativeReport = AuditReport(
        title: "2026-04-22 原生报告",
        sourcePath: "/tmp/native.html",
        scanDirectoryPath: "/tmp/date",
        metrics: [],
        sections: [section]
    )
    let legacyReport = AuditReport(
        title: "2026-04-20 Legacy 报告",
        sourcePath: "/tmp/legacy.html",
        scanDirectoryPath: "/tmp/date",
        isLegacy: true,
        metrics: [],
        sections: [ReportSection(kind: .overview, title: "Legacy 报告", summary: "旧版导入")]
    )

    #expect(nativeReport.matchesLibrarySearch("结构片段", filter: .all))
    #expect(nativeReport.matchesLibrarySearch("原生", filter: .nativeOnly))
    #expect(legacyReport.matchesLibrarySearch("", filter: .legacyOnly))
}

@Test
func sectionFilteringRespectsQueryFilterAndSortOrder() {
    let section = ReportSection(
        kind: .image,
        title: "图片证据详列",
        summary: "支持 OCR 证据",
        table: ReportTable(
            headers: ["文件 A", "文件 B"],
            rows: [
                ReportTableRow(
                    columns: ["b.png", "c.png"],
                    detailTitle: "B 组",
                    detailBody: "包含截图",
                    badges: [ReportBadge(title: "关注", tone: .warning)],
                    attachments: [ReportAttachment(title: "A", subtitle: "图", body: "证据", imageBase64: nil)]
                ),
                ReportTableRow(
                    columns: ["a.png", "d.png"],
                    detailTitle: "A 组",
                    detailBody: "高危匹配",
                    badges: [ReportBadge(title: "高危", tone: .danger)],
                    attachments: []
                )
            ]
        )
    )

    let attachmentOnly = section.filteredCopy(query: "", evidenceFilter: .withAttachments, sortOrder: .default)
    #expect(attachmentOnly.table?.rows.count == 1)
    #expect(attachmentOnly.table?.rows.first?.detailTitle == "B 组")

    let highRisk = section.filteredCopy(query: "高危", evidenceFilter: .highRisk, sortOrder: .severity)
    #expect(highRisk.table?.rows.count == 1)
    #expect(highRisk.table?.rows.first?.detailTitle == "A 组")

    let titled = section.filteredCopy(query: "", evidenceFilter: .all, sortOrder: .title)
    #expect(titled.table?.rows.map(\.detailTitle) == ["A 组", "B 组"])
}

@Test
func pdfIngestionExtractsEmbeddedImagesBeforePageFallback() throws {
    let fileManager = FileManager.default
    var root = ProjectLocator().workspaceRoot()
    for _ in 0..<6 {
        if fileManager.fileExists(atPath: root.appendingPathComponent("date").path) {
            break
        }
        root.deleteLastPathComponent()
    }
    let fixtureDirectory = root.appendingPathComponent("date/date6/145-flag{LNU_cyber}")

    var configuration = AuditConfiguration.defaults(for: root)
    configuration.directoryPath = fixtureDirectory.path
    configuration.useVisionOCR = false

    let documents = try DocumentIngestionService(configuration: configuration).ingestDocuments(in: fixtureDirectory)
    let pdfDocument = try #require(documents.first(where: { $0.ext == "pdf" }))

    #expect(pdfDocument.images.isEmpty == false)
    #expect(pdfDocument.images.contains(where: { $0.source.contains(":X") }))
}
