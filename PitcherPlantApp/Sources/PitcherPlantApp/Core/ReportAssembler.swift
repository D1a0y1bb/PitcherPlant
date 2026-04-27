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

