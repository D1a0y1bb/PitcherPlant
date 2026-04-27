import Foundation

struct RiskScoringService {
    private let weights: [EvidenceType: Double] = [
        .text: 0.30,
        .code: 0.25,
        .image: 0.20,
        .metadata: 0.10,
        .dedup: 0.20,
        .crossBatch: 0.15,
    ]

    func evidenceRecords(
        textPairs: [SuspiciousPair],
        codePairs: [SuspiciousPair],
        imagePairs: [SuspiciousPair],
        metadataCollisions: [MetadataCollision],
        dedupPairs: [SuspiciousPair],
        crossBatch: [CrossBatchMatch]
    ) -> [EvidenceRecord] {
        var records: [EvidenceRecord] = []
        records += textPairs.map { record(from: $0, type: .text, reason: "文本高相似") }
        records += codePairs.map { record(from: $0, type: .code, reason: "代码结构相似") }
        records += imagePairs.map { record(from: $0, type: .image, reason: "图片复用") }
        records += dedupPairs.map { record(from: $0, type: .dedup, reason: "重复提交") }
        records += metadataRecords(from: metadataCollisions)
        records += crossBatch.map { record(from: $0) }
        return records
    }

    func aggregate(records: [EvidenceRecord]) -> [RiskAggregate] {
        struct Bucket {
            var records: [EvidenceRecord] = []
            var contribution: Double = 0
            var reasons: Set<String> = []
            var types: Set<EvidenceType> = []
        }

        var buckets: [String: Bucket] = [:]
        for record in records {
            let key = pairKey(record.fileA, record.fileB)
            var bucket = buckets[key, default: Bucket()]
            bucket.records.append(record)
            bucket.types.insert(record.type)
            bucket.reasons.formUnion(record.riskAssessment.reasons)
            bucket.contribution += (weights[record.type] ?? 0.10) * normalizedScore(for: record)
            buckets[key] = bucket
        }

        return buckets.map { key, bucket in
            let parts = key.components(separatedBy: "|||")
            let bonus = min(0.10, max(0, Double(bucket.types.count - 1) * 0.04))
            let score = min(1.0, bucket.contribution + bonus)
            let reasons = bucket.reasons.sorted()
            let assessment = RiskAssessment(
                score: score,
                reasons: reasons.isEmpty ? bucket.types.map(\.title).sorted() : reasons,
                evidenceCount: bucket.records.count
            )
            return RiskAggregate(
                id: UUID.pitcherPlantStable(namespace: "risk-aggregate", components: [key]),
                fileA: parts.first ?? "",
                fileB: parts.dropFirst().first ?? "",
                assessment: assessment,
                evidenceTypes: bucket.types.sorted { $0.rawValue < $1.rawValue },
                records: bucket.records.sorted { $0.score > $1.score }
            )
        }
        .sorted {
            if $0.assessment.score == $1.assessment.score {
                return $0.fileA.localizedStandardCompare($1.fileA) == .orderedAscending
            }
            return $0.assessment.score > $1.assessment.score
        }
    }

    private func record(from pair: SuspiciousPair, type: EvidenceType, reason: String) -> EvidenceRecord {
        EvidenceRecord(
            type: type,
            fileA: pair.fileA,
            fileB: pair.fileB,
            score: pair.score,
            evidence: pair.evidence,
            detailLines: pair.detailLines,
            attachments: pair.attachments,
            riskAssessment: RiskAssessment(score: pair.score, reasons: [reason]),
            whitelistEvaluation: pair.whitelistEvaluation
        )
    }

    private func metadataRecords(from collisions: [MetadataCollision]) -> [EvidenceRecord] {
        var records: [EvidenceRecord] = []
        for collision in collisions {
            for left in collision.files.indices {
                for right in collision.files.indices where right > left {
                    let score = 0.70 * (collision.whitelistEvaluation?.scoreMultiplier ?? 1)
                    records.append(
                        EvidenceRecord(
                            type: .metadata,
                            fileA: collision.files[left],
                            fileB: collision.files[right],
                            score: score,
                            evidence: "共同元数据：\(collision.author)",
                            detailLines: [
                                "作者或最后修改者：\(collision.author)",
                                "涉及文件数：\(collision.files.count)"
                            ],
                            riskAssessment: RiskAssessment(
                                score: score,
                                reasons: ["元数据碰撞"]
                            ),
                            whitelistEvaluation: collision.whitelistEvaluation
                        )
                    )
                }
            }
        }
        return records
    }

    private func record(from match: CrossBatchMatch) -> EvidenceRecord {
        let score = max(0, 1.0 - (Double(match.distance) / 16.0))
        let adjustedScore = score * (match.whitelistEvaluation?.scoreMultiplier ?? 1)
        return EvidenceRecord(
            type: .crossBatch,
            fileA: match.currentFile,
            fileB: match.previousFile,
            score: adjustedScore,
            evidence: "\(match.previousScan) / \(match.status)",
            detailLines: [
                "历史批次：\(match.previousScan)",
                "SimHash 位差：\(match.distance)",
                "状态：\(match.status)"
            ],
            riskAssessment: RiskAssessment(score: adjustedScore, reasons: ["跨批次复用"]),
            whitelistEvaluation: match.whitelistEvaluation
        )
    }

    private func normalizedScore(for record: EvidenceRecord) -> Double {
        switch record.type {
        case .metadata:
            return record.whitelistEvaluation == nil ? 1 : record.score
        case .crossBatch:
            return max(record.score, 0.40)
        default:
            return record.score
        }
    }

    private func pairKey(_ left: String, _ right: String) -> String {
        [left, right].sorted().joined(separator: "|||")
    }
}

enum EvidenceRecordFactory {
    static func rows(
        from records: [EvidenceRecord],
        type: EvidenceType,
        label: String,
        extraBadges: [ReportBadge] = []
    ) -> [ReportTableRow] {
        records
            .filter { $0.type == type }
            .sorted {
                if $0.riskAssessment.score == $1.riskAssessment.score {
                    return $0.fileA.localizedStandardCompare($1.fileA) == .orderedAscending
                }
                return $0.riskAssessment.score > $1.riskAssessment.score
            }
            .map { $0.reportRow(label: label, extraBadges: extraBadges) }
    }

    static func overviewRows(from aggregates: [RiskAggregate]) -> [ReportTableRow] {
        aggregates.map { aggregate in
            let badge = ReportBadge(
                title: "\(aggregate.assessment.level.title)风险 \(aggregate.assessment.formattedScore)",
                tone: aggregate.assessment.level.badgeTone
            )
            let typeBadge = ReportBadge(
                title: aggregate.evidenceTypes.map(\.title).joined(separator: " / "),
                tone: .accent
            )
            return ReportTableRow(
                id: aggregate.id,
                columns: [
                    aggregate.fileA,
                    aggregate.fileB,
                    aggregate.assessment.formattedScore,
                    aggregate.reasonSummary,
                    "\(aggregate.assessment.evidenceCount)"
                ],
                detailTitle: "\(aggregate.fileA) ↔ \(aggregate.fileB)",
                detailBody: [
                    "综合风险：\(aggregate.assessment.formattedScore)",
                    "风险等级：\(aggregate.assessment.level.title)",
                    "证据数量：\(aggregate.assessment.evidenceCount)",
                    "命中原因：\(aggregate.reasonSummary)"
                ].joined(separator: "\n"),
                badges: [badge, typeBadge],
                attachments: aggregate.records.flatMap(\.attachments),
                evidenceID: aggregate.id,
                evidenceType: nil,
                riskAssessment: aggregate.assessment
            )
        }
    }
}
