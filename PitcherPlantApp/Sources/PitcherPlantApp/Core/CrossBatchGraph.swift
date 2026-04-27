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
    enum Kind: String, Codable, Hashable, Sendable {
        case document
        case team
        case batch
        case challenge
        case fingerprint

        var title: String {
            switch self {
            case .document: return "文档"
            case .team: return "队伍"
            case .batch: return "批次"
            case .challenge: return "题目"
            case .fingerprint: return "指纹"
            }
        }

        var systemImage: String {
            switch self {
            case .document: return "doc.text"
            case .team: return "person.2"
            case .batch: return "archivebox"
            case .challenge: return "flag"
            case .fingerprint: return "number"
            }
        }
    }

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
    let kind: Kind
    let fileName: String
    let role: Role
    let batchName: String?
    let teamName: String?
    let challengeName: String?
    let simhash: String?
    let author: String?
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case fileName
        case role
        case batchName
        case teamName
        case challengeName
        case simhash
        case author
        case tags
    }

    var subtitle: String {
        [batchName, teamName, challengeName]
            .compactMap { normalized($0) }
            .joined(separator: " / ")
    }

    init(
        id: String,
        kind: Kind = .document,
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
        self.kind = kind
        self.fileName = fileName
        self.role = role
        self.batchName = normalized(batchName)
        self.teamName = normalized(teamName)
        self.challengeName = normalized(challengeName)
        self.simhash = normalized(simhash)
        self.author = normalized(author)
        self.tags = normalizedTags(tags)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            kind: try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .document,
            fileName: try container.decode(String.self, forKey: .fileName),
            role: try container.decode(Role.self, forKey: .role),
            batchName: try container.decodeIfPresent(String.self, forKey: .batchName),
            teamName: try container.decodeIfPresent(String.self, forKey: .teamName),
            challengeName: try container.decodeIfPresent(String.self, forKey: .challengeName),
            simhash: try container.decodeIfPresent(String.self, forKey: .simhash),
            author: try container.decodeIfPresent(String.self, forKey: .author),
            tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
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
    let currentSimhash: String?
    let historicalSimhash: String?
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
        let contextNodes = nodes.filter { node in
            node.kind != .document && filteredEdges.contains { edge in node.matches(edge: edge) }
        }
        return CrossBatchGraph(
            nodes: nodes.filter { nodeIDs.contains($0.id) } + contextNodes.filter { nodeIDs.contains($0.id) == false },
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
                kind: .document,
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
                kind: .document,
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
                currentSimhash: match.currentSimhash,
                historicalSimhash: match.historicalSimhash,
                tags: match.tags,
                riskScore: nil,
                evidenceID: nil
            ))
            upsertContextNodes(
                role: .current,
                batchName: match.currentBatchName,
                teamName: match.currentTeamName,
                challengeName: match.currentChallengeName,
                simhash: match.currentSimhash,
                author: match.currentAuthor,
                tags: match.tags,
                nodesByID: &nodesByID
            )
            upsertContextNodes(
                role: .historical,
                batchName: match.displayBatchName,
                teamName: match.teamName,
                challengeName: match.challengeName,
                simhash: match.historicalSimhash,
                author: match.historicalAuthor,
                tags: match.tags,
                nodesByID: &nodesByID
            )
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
                kind: .document,
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
                kind: .document,
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
                currentSimhash: currentSimhash,
                historicalSimhash: historicalSimhash,
                tags: tags,
                riskScore: row.riskAssessment?.score,
                evidenceID: row.evidenceID ?? row.id
            ))
            upsertContextNodes(
                role: .current,
                batchName: currentBatchName,
                teamName: currentTeamName,
                challengeName: currentChallengeName,
                simhash: currentSimhash,
                author: metadata[CrossBatchGraphMetadataKey.currentAuthor],
                tags: tags,
                nodesByID: &nodesByID
            )
            upsertContextNodes(
                role: .historical,
                batchName: batchName,
                teamName: teamName,
                challengeName: challengeName,
                simhash: historicalSimhash,
                author: metadata[CrossBatchGraphMetadataKey.historicalAuthor],
                tags: tags,
                nodesByID: &nodesByID
            )
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

    private func upsertContextNodes(
        role: CrossBatchGraphNode.Role,
        batchName: String?,
        teamName: String?,
        challengeName: String?,
        simhash: String?,
        author: String?,
        tags: [String],
        nodesByID: inout [String: CrossBatchGraphNode]
    ) {
        upsertContextNode(kind: .batch, role: role, name: batchName, batchName: batchName, teamName: nil, challengeName: nil, simhash: nil, author: nil, tags: tags, nodesByID: &nodesByID)
        upsertContextNode(kind: .team, role: role, name: teamName, batchName: batchName, teamName: teamName, challengeName: nil, simhash: nil, author: author, tags: tags, nodesByID: &nodesByID)
        upsertContextNode(kind: .challenge, role: role, name: challengeName, batchName: batchName, teamName: teamName, challengeName: challengeName, simhash: nil, author: nil, tags: tags, nodesByID: &nodesByID)
        upsertContextNode(kind: .fingerprint, role: role, name: simhash, batchName: batchName, teamName: teamName, challengeName: challengeName, simhash: simhash, author: author, tags: tags, nodesByID: &nodesByID)
    }

    private func upsertContextNode(
        kind: CrossBatchGraphNode.Kind,
        role: CrossBatchGraphNode.Role,
        name: String?,
        batchName: String?,
        teamName: String?,
        challengeName: String?,
        simhash: String?,
        author: String?,
        tags: [String],
        nodesByID: inout [String: CrossBatchGraphNode]
    ) {
        guard let name = normalized(name) else { return }
        let id = nodeID(role: role, fileName: "\(kind.rawValue):\(name)", components: [
            batchName,
            teamName,
            challengeName,
            simhash,
        ])
        nodesByID[id] = CrossBatchGraphNode(
            id: id,
            kind: kind,
            fileName: name,
            role: role,
            batchName: batchName,
            teamName: teamName,
            challengeName: challengeName,
            simhash: simhash,
            author: author,
            tags: tags
        )
    }

    private func tags(from value: String?) -> [String] {
        normalizedTags(value?.split(separator: ",").map(String.init) ?? [])
    }

    private func sorted(_ nodes: Dictionary<String, CrossBatchGraphNode>.Values) -> [CrossBatchGraphNode] {
        nodes.sorted {
            if $0.kind != $1.kind {
                return $0.kind.rawValue < $1.kind.rawValue
            }
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

private extension CrossBatchGraphNode {
    func matches(edge: CrossBatchGraphEdge) -> Bool {
        switch role {
        case .current:
            return matchesCurrent(edge)
        case .historical:
            return matchesHistorical(edge)
        }
    }

    private func matchesCurrent(_ edge: CrossBatchGraphEdge) -> Bool {
        switch kind {
        case .document:
            return id == edge.sourceID
        case .batch:
            return normalized(batchName) == normalized(edge.currentBatchName)
        case .team:
            return normalized(teamName) == normalized(edge.currentTeamName)
        case .challenge:
            return normalized(challengeName) == normalized(edge.currentChallengeName)
        case .fingerprint:
            return normalized(simhash) == normalized(edge.currentSimhash)
        }
    }

    private func matchesHistorical(_ edge: CrossBatchGraphEdge) -> Bool {
        switch kind {
        case .document:
            return id == edge.targetID
        case .batch:
            return normalized(batchName) == normalized(edge.batchName)
        case .team:
            return normalized(teamName) == normalized(edge.teamName)
        case .challenge:
            return normalized(challengeName) == normalized(edge.challengeName)
        case .fingerprint:
            return normalized(simhash) == normalized(edge.historicalSimhash)
        }
    }
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
