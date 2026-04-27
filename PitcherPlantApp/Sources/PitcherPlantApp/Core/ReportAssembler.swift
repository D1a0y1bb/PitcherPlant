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
        let crossBatchRows = crossBatchRows(matches: crossBatch, records: evidenceRecords)
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
                            detailBody: fingerprintDetailBody(for: $0),
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
                    rows: crossBatchRows
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

    private func crossBatchRows(matches: [CrossBatchMatch], records: [EvidenceRecord]) -> [ReportTableRow] {
        let crossBatchRecords = records.filter { $0.type == .crossBatch }
        return matches.sorted {
            if $0.distance == $1.distance {
                return $0.currentFile.localizedStandardCompare($1.currentFile) == .orderedAscending
            }
            return $0.distance < $1.distance
        }
        .map { match in
            let record = crossBatchRecords.first { record in
                record.fileA == match.currentFile
                    && record.fileB == match.previousFile
                    && record.evidence.contains(match.previousScan)
            } ?? crossBatchRecords.first { record in
                record.fileA == match.currentFile && record.fileB == match.previousFile
            }
            let score = max(0, 1.0 - (Double(match.distance) / 16.0))
            let assessment = record?.riskAssessment ?? RiskAssessment(score: score, reasons: ["跨批次复用"])
            let evidenceID = record?.id ?? UUID.pitcherPlantStable(
                namespace: "cross-batch-evidence",
                components: [match.currentFile, match.previousFile, match.previousScan, "\(match.distance)", match.status]
            )
            let riskBadge = ReportBadge(title: "\(assessment.level.title)风险 \(assessment.formattedScore)", tone: assessment.level.badgeTone)
            let statusBadge = ReportBadge(title: match.status, tone: match.status.contains("白名单") ? .success : .danger)
            return ReportTableRow(
                id: evidenceID,
                columns: [
                    match.currentFile,
                    match.previousFile,
                    match.displayBatchName,
                    "\(match.distance)",
                    match.status,
                ],
                detailTitle: "\(match.currentFile) ↔ \(match.previousFile)",
                detailBody: crossBatchDetailBody(match: match, assessment: assessment, record: record),
                badges: [riskBadge, statusBadge],
                attachments: record?.attachments ?? [],
                evidenceID: evidenceID,
                evidenceType: .crossBatch,
                riskAssessment: assessment,
                metadata: crossBatchMetadata(for: match),
                whitelistStatus: match.whitelistEvaluation ?? record?.whitelistEvaluation
            )
        }
    }

    private func crossBatchDetailBody(match: CrossBatchMatch, assessment: RiskAssessment, record: EvidenceRecord?) -> String {
        var lines = [
            "当前文件：\(match.currentFile)",
            "历史文件：\(match.previousFile)",
            "历史批次：\(match.displayBatchName)",
            "历史扫描目录：\(match.previousScan)",
            "SimHash 位差：\(match.distance)",
            "状态：\(match.status)",
        ]
        append("历史报告 ID", match.sourceReportID?.uuidString, to: &lines)
        append("历史队伍", match.teamName, to: &lines)
        append("历史题目", match.challengeName, to: &lines)
        append("当前批次", match.currentBatchName, to: &lines)
        append("当前队伍", match.currentTeamName, to: &lines)
        append("当前题目", match.currentChallengeName, to: &lines)
        append("当前作者", match.currentAuthor, to: &lines)
        append("历史作者", match.historicalAuthor, to: &lines)
        append("当前 SimHash", match.currentSimhash, to: &lines)
        append("历史 SimHash", match.historicalSimhash, to: &lines)
        if match.tags.isEmpty == false {
            lines.append("标签：\(match.tags.joined(separator: "、"))")
        }
        if assessment.reasons.isEmpty == false {
            lines.append("风险原因：\(assessment.reasons.joined(separator: "、"))")
        }
        if let evaluation = match.whitelistEvaluation ?? record?.whitelistEvaluation, evaluation.isClear == false {
            lines.append("白名单：\(evaluation.exportSummary)")
        }
        if let record, record.detailLines.isEmpty == false {
            lines.append(record.detailLines.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }

    private func crossBatchMetadata(for match: CrossBatchMatch) -> [String: String] {
        var metadata: [String: String] = [
            CrossBatchGraphMetadataKey.batchName: match.displayBatchName,
            CrossBatchGraphMetadataKey.previousScan: match.previousScan,
            CrossBatchGraphMetadataKey.status: match.status,
            CrossBatchGraphMetadataKey.distance: "\(match.distance)",
        ]
        put(match.sourceReportID?.uuidString, for: CrossBatchGraphMetadataKey.sourceReportID, into: &metadata)
        put(match.teamName, for: CrossBatchGraphMetadataKey.teamName, into: &metadata)
        put(match.challengeName, for: CrossBatchGraphMetadataKey.challengeName, into: &metadata)
        put(match.currentBatchName, for: CrossBatchGraphMetadataKey.currentBatchName, into: &metadata)
        put(match.currentTeamName, for: CrossBatchGraphMetadataKey.currentTeamName, into: &metadata)
        put(match.currentChallengeName, for: CrossBatchGraphMetadataKey.currentChallengeName, into: &metadata)
        put(match.currentSimhash, for: CrossBatchGraphMetadataKey.currentSimhash, into: &metadata)
        put(match.historicalSimhash, for: CrossBatchGraphMetadataKey.historicalSimhash, into: &metadata)
        put(match.currentAuthor, for: CrossBatchGraphMetadataKey.currentAuthor, into: &metadata)
        put(match.historicalAuthor, for: CrossBatchGraphMetadataKey.historicalAuthor, into: &metadata)
        if match.tags.isEmpty == false {
            metadata[CrossBatchGraphMetadataKey.tags] = match.tags.joined(separator: ",")
        }
        return metadata
    }

    private func fingerprintDetailBody(for record: FingerprintRecord) -> String {
        var lines = [
            "作者：\(record.author)",
            "扩展名：\(record.ext)",
            "字符数：\(record.size)",
            "SimHash：\(record.simhash)",
            "扫描目录：\(record.scanDir)",
        ]
        append("来源报告 ID", record.sourceReportID?.uuidString, to: &lines)
        append("批次", record.batchName, to: &lines)
        append("队伍", record.teamName, to: &lines)
        append("题目", record.challengeName, to: &lines)
        append("提交 ID", record.submissionItemID?.uuidString, to: &lines)
        if let tags = record.tags, tags.isEmpty == false {
            lines.append("标签：\(tags.joined(separator: "、"))")
        }
        return lines.joined(separator: "\n")
    }

    private func append(_ label: String, _ value: String?, to lines: inout [String]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return }
        lines.append("\(label)：\(trimmed)")
    }

    private func put(_ value: String?, for key: String, into metadata: inout [String: String]) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else { return }
        metadata[key] = trimmed
    }
}
