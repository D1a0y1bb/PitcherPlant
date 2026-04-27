import Foundation

enum CrossBatchGraphMetadataKey {
    static let batchName = "crossBatch.batchName"
    static let previousScan = "crossBatch.previousScan"
    static let teamName = "crossBatch.teamName"
    static let challengeName = "crossBatch.challengeName"
    static let sourceReportID = "crossBatch.sourceReportID"
    static let currentBatchName = "crossBatch.currentBatchName"
    static let currentTeamName = "crossBatch.currentTeamName"
    static let currentChallengeName = "crossBatch.currentChallengeName"
    static let currentSimhash = "crossBatch.currentSimhash"
    static let historicalSimhash = "crossBatch.historicalSimhash"
    static let currentAuthor = "crossBatch.currentAuthor"
    static let historicalAuthor = "crossBatch.historicalAuthor"
    static let tags = "crossBatch.tags"
    static let status = "crossBatch.status"
    static let distance = "crossBatch.distance"
}

struct CrossBatchGraphNode: Codable, Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case current
        case historical

        var title: String {
            switch self {
            case .current: return "当前"
            case .historical: return "历史"
            }
        }
    }

    let id: String
    let fileName: String
    let role: Role
    let batchName: String?
    let teamName: String?
    let challengeName: String?
    let simhash: String?
    let author: String?
    let tags: [String]

    var subtitle: String {
        [batchName, teamName, challengeName]
            .compactMap { normalized($0) }
            .joined(separator: " / ")
    }

    init(
        id: String,
        fileName: String,
        role: Role,
        batchName: String? = nil,
        teamName: String? = nil,
        challengeName: String? = nil,
        simhash: String? = nil,
        author: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.fileName = fileName
        self.role = role
        self.batchName = normalized(batchName)
        self.teamName = normalized(teamName)
        self.challengeName = normalized(challengeName)
        self.simhash = normalized(simhash)
        self.author = normalized(author)
        self.tags = normalizedTags(tags)
    }
}

struct CrossBatchGraphEdge: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let currentFile: String
    let historicalFile: String
    let batchName: String?
    let currentBatchName: String?
    let teamName: String?
    let currentTeamName: String?
    let challengeName: String?
    let currentChallengeName: String?
    let status: String
    let distance: Int
    let tags: [String]
    let riskScore: Double?
    let evidenceID: UUID?

    var displayBatchName: String {
        normalized(batchName) ?? "未标注批次"
    }

    var teamNames: [String] {
        normalizedTags([currentTeamName, teamName].compactMap { $0 })
    }
}

struct CrossBatchGraph: Codable, Hashable, Sendable {
    var nodes: [CrossBatchGraphNode]
    var edges: [CrossBatchGraphEdge]

    var batches: [String] {
        uniqueSorted(edges.compactMap(\.batchName))
    }

    var teams: [String] {
        uniqueSorted(edges.flatMap(\.teamNames))
    }

    var tags: [String] {
        uniqueSorted(edges.flatMap(\.tags))
    }

    var statuses: [String] {
        uniqueSorted(edges.map(\.status))
    }

    func filtered(batch: String?, team: String?, tag: String?, status: String?) -> CrossBatchGraph {
        let filteredEdges = edges.filter { edge in
            matches(batch, value: edge.batchName)
                && matches(team, values: edge.teamNames)
                && matches(tag, values: edge.tags)
                && matches(status, value: edge.status)
        }
        let nodeIDs = Set(filteredEdges.flatMap { [$0.sourceID, $0.targetID] })
        return CrossBatchGraph(
            nodes: nodes.filter { nodeIDs.contains($0.id) },
            edges: filteredEdges
        )
    }

    private func matches(_ filter: String?, value: String?) -> Bool {
        guard let filter = normalized(filter) else { return true }
        return normalized(value) == filter
    }

    private func matches(_ filter: String?, values: [String]) -> Bool {
        guard let filter = normalized(filter) else { return true }
        return values.contains(filter)
    }
}

struct CrossBatchGraphBuilder {
    func build(matches: [CrossBatchMatch]) -> CrossBatchGraph {
        var nodesByID: [String: CrossBatchGraphNode] = [:]
        var edges: [CrossBatchGraphEdge] = []

        for match in matches {
            let currentID = nodeID(role: .current, fileName: match.currentFile, components: [
                match.currentBatchName,
                match.currentTeamName,
                match.currentChallengeName,
                match.currentSimhash,
            ])
            let historicalID = nodeID(role: .historical, fileName: match.previousFile, components: [
                match.sourceReportID?.uuidString,
                match.batchName,
                match.teamName,
                match.challengeName,
                match.historicalSimhash,
            ])
            nodesByID[currentID] = CrossBatchGraphNode(
                id: currentID,
                fileName: match.currentFile,
                role: .current,
                batchName: match.currentBatchName,
                teamName: match.currentTeamName,
                challengeName: match.currentChallengeName,
                simhash: match.currentSimhash,
                author: match.currentAuthor,
                tags: match.tags
            )
            nodesByID[historicalID] = CrossBatchGraphNode(
                id: historicalID,
                fileName: match.previousFile,
                role: .historical,
                batchName: match.displayBatchName,
                teamName: match.teamName,
                challengeName: match.challengeName,
                simhash: match.historicalSimhash,
                author: match.historicalAuthor,
                tags: match.tags
            )
            edges.append(CrossBatchGraphEdge(
                id: edgeID(currentID: currentID, historicalID: historicalID, distance: match.distance, status: match.status),
                sourceID: currentID,
                targetID: historicalID,
                currentFile: match.currentFile,
                historicalFile: match.previousFile,
                batchName: match.displayBatchName,
                currentBatchName: match.currentBatchName,
                teamName: match.teamName,
                currentTeamName: match.currentTeamName,
                challengeName: match.challengeName,
                currentChallengeName: match.currentChallengeName,
                status: match.status,
                distance: match.distance,
                tags: match.tags,
                riskScore: nil,
                evidenceID: nil
            ))
        }

        return CrossBatchGraph(nodes: sorted(nodesByID.values), edges: sorted(edges))
    }

    func build(rows: [ReportTableRow]) -> CrossBatchGraph {
        var nodesByID: [String: CrossBatchGraphNode] = [:]
        var edges: [CrossBatchGraphEdge] = []

        for row in rows {
            let metadata = row.metadata ?? [:]
            let currentFile = row.columns.element(at: 0) ?? row.detailTitle
            let historicalFile = row.columns.element(at: 1) ?? ""
            let batchName = metadata[CrossBatchGraphMetadataKey.batchName] ?? row.columns.element(at: 2)
            let currentBatchName = metadata[CrossBatchGraphMetadataKey.currentBatchName]
            let teamName = metadata[CrossBatchGraphMetadataKey.teamName]
            let currentTeamName = metadata[CrossBatchGraphMetadataKey.currentTeamName]
            let challengeName = metadata[CrossBatchGraphMetadataKey.challengeName]
            let currentChallengeName = metadata[CrossBatchGraphMetadataKey.currentChallengeName]
            let tags = tags(from: metadata[CrossBatchGraphMetadataKey.tags])
            let status = metadata[CrossBatchGraphMetadataKey.status] ?? row.columns.element(at: 4) ?? row.badges.first?.title ?? "待复核"
            let distance = Int(metadata[CrossBatchGraphMetadataKey.distance] ?? row.columns.element(at: 3) ?? "") ?? 0
            let currentSimhash = metadata[CrossBatchGraphMetadataKey.currentSimhash]
            let historicalSimhash = metadata[CrossBatchGraphMetadataKey.historicalSimhash]

            let currentID = nodeID(role: .current, fileName: currentFile, components: [
                currentBatchName,
                currentTeamName,
                currentChallengeName,
                currentSimhash,
            ])
            let historicalID = nodeID(role: .historical, fileName: historicalFile, components: [
                metadata[CrossBatchGraphMetadataKey.sourceReportID],
                batchName,
                teamName,
                challengeName,
                historicalSimhash,
            ])

            nodesByID[currentID] = CrossBatchGraphNode(
                id: currentID,
                fileName: currentFile,
                role: .current,
                batchName: currentBatchName,
                teamName: currentTeamName,
                challengeName: currentChallengeName,
                simhash: currentSimhash,
                author: metadata[CrossBatchGraphMetadataKey.currentAuthor],
                tags: tags
            )
            nodesByID[historicalID] = CrossBatchGraphNode(
                id: historicalID,
                fileName: historicalFile,
                role: .historical,
                batchName: batchName,
                teamName: teamName,
                challengeName: challengeName,
                simhash: historicalSimhash,
                author: metadata[CrossBatchGraphMetadataKey.historicalAuthor],
                tags: tags
            )

            edges.append(CrossBatchGraphEdge(
                id: edgeID(currentID: currentID, historicalID: historicalID, distance: distance, status: status),
                sourceID: currentID,
                targetID: historicalID,
                currentFile: currentFile,
                historicalFile: historicalFile,
                batchName: batchName,
                currentBatchName: currentBatchName,
                teamName: teamName,
                currentTeamName: currentTeamName,
                challengeName: challengeName,
                currentChallengeName: currentChallengeName,
                status: status,
                distance: distance,
                tags: tags,
                riskScore: row.riskAssessment?.score,
                evidenceID: row.evidenceID ?? row.id
            ))
        }

        return CrossBatchGraph(nodes: sorted(nodesByID.values), edges: sorted(edges))
    }

    private func nodeID(role: CrossBatchGraphNode.Role, fileName: String, components: [String?]) -> String {
        let identity = ([fileName] + components.compactMap { normalized($0) }).joined(separator: "|")
        return "\(role.rawValue):\(UUID.pitcherPlantStable(namespace: "cross-batch-node", components: [role.rawValue, identity]).uuidString)"
    }

    private func edgeID(currentID: String, historicalID: String, distance: Int, status: String) -> String {
        UUID.pitcherPlantStable(
            namespace: "cross-batch-edge",
            components: [currentID, historicalID, "\(distance)", status]
        ).uuidString
    }

    private func tags(from value: String?) -> [String] {
        normalizedTags(value?.split(separator: ",").map(String.init) ?? [])
    }

    private func sorted(_ nodes: Dictionary<String, CrossBatchGraphNode>.Values) -> [CrossBatchGraphNode] {
        nodes.sorted {
            if $0.role == $1.role {
                return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
            return $0.role.rawValue < $1.role.rawValue
        }
    }

    private func sorted(_ edges: [CrossBatchGraphEdge]) -> [CrossBatchGraphEdge] {
        edges.sorted {
            if $0.distance == $1.distance {
                return $0.currentFile.localizedStandardCompare($1.currentFile) == .orderedAscending
            }
            return $0.distance < $1.distance
        }
    }
}

private func normalized(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedTags(_ values: [String]) -> [String] {
    Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false })).sorted()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    normalizedTags(values)
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
