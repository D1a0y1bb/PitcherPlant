import Foundation

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
        let riskService = RiskScoringService()
        let evidenceRecords = riskService.evidenceRecords(
            textPairs: textPairs,
            codePairs: codePairs,
            imagePairs: imagePairs,
            metadataCollisions: metadataCollisions,
            dedupPairs: dedupPairs,
            crossBatch: crossBatch
        )
        let riskAggregates = riskService.aggregate(records: evidenceRecords)
        let overviewRows = EvidenceRecordFactory.overviewRows(from: riskAggregates)
        let highRiskCount = riskAggregates.filter { $0.assessment.level == .high }.count

        let metrics = [
            ReportMetric(title: "文本/代码高危相似", value: "\(textPairs.count + codePairs.count)", systemImage: "exclamationmark.triangle.fill"),
            ReportMetric(title: "图片雷同组合", value: "\(imagePairs.count)", systemImage: "photo.fill.on.rectangle.fill"),
            ReportMetric(title: "元数据碰撞", value: "\(metadataCollisions.count)", systemImage: "person.crop.rectangle"),
            ReportMetric(title: "高风险文件对", value: "\(highRiskCount)", systemImage: "flame.fill"),
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
                    headers: ["对象 A", "对象 B", "综合风险", "命中原因", "证据数"],
                    rows: overviewRows
                )
            ),
            ReportSection(
                kind: .text,
                title: "文本内容相似度分析",
                summary: "基于原生 TF-IDF + cosine 的文本相似度分析。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .text, label: "文本相似度")
                )
            ),
            ReportSection(
                kind: .code,
                title: "代码/脚本抄袭分析",
                summary: "提取 fenced code 与启发式代码片段，按 token shingles 和结构 token 做比对。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .code, label: "代码结构相似度", extraBadges: [ReportBadge(title: "代码", tone: .accent)])
                )
            ),
            ReportSection(
                kind: .image,
                title: "图片证据详列",
                summary: "当前版本支持 DOCX 嵌入媒体与 PDF 内嵌图片提取，页级缩略图只在无法解析图片流时兜底。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .image, label: "图片相似度", extraBadges: [ReportBadge(title: "图片", tone: .warning)])
                )
            ),
            ReportSection(
                kind: .metadata,
                title: "元数据碰撞",
                summary: "按作者等元数据字段聚合可能存在的交叉来源。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .metadata, label: "元数据碰撞", extraBadges: [ReportBadge(title: "元数据", tone: .neutral)])
                )
            ),
            ReportSection(
                kind: .dedup,
                title: "重复文件去重报告",
                summary: "按更严格阈值列出疑似重复或高度改写的文件对。",
                table: ReportTable(
                    headers: ["文件 A", "文件 B", "相似度", "证据"],
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .dedup, label: "重复检测相似度", extraBadges: [ReportBadge(title: "重复", tone: .warning)])
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
                    rows: EvidenceRecordFactory.rows(from: evidenceRecords, type: .crossBatch, label: "跨批次复用")
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
}
