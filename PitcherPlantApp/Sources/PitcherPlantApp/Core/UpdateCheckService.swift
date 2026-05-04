import Foundation

struct UpdateReleaseAsset: Equatable, Sendable {
    let name: String
    let downloadURL: URL
    let size: Int?

    var displaySize: String {
        guard let size else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct UpdateReleaseInfo: Equatable, Sendable {
    let tagName: String
    let name: String
    let version: String
    let htmlURL: URL
    let publishedAt: Date?
    let body: String
    let assets: [UpdateReleaseAsset]

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? tagName : name
    }

    var primaryDownload: UpdateReleaseAsset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
            ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
            ?? assets.first
    }
}

enum UpdateAvailability: Equatable, Sendable {
    case updateAvailable
    case upToDate
    case unknown

    static func resolve(current: String, latest: String) -> UpdateAvailability {
        guard let currentVersion = AppSemanticVersion(current),
              let latestVersion = AppSemanticVersion(latest) else {
            return .unknown
        }
        return latestVersion > currentVersion ? .updateAvailable : .upToDate
    }
}

struct UpdateCheckResult: Equatable, Sendable {
    let currentVersion: AppVersionInfo
    let latestRelease: UpdateReleaseInfo
    let availability: UpdateAvailability
    let checkedAt: Date
}

enum UpdateCheckError: LocalizedError, Equatable {
    case missingUpdateURL
    case releaseNotFound
    case httpStatus(Int)
    case emptyReleaseFeed

    var errorDescription: String? {
        switch self {
        case .missingUpdateURL:
            return "更新源尚未配置。"
        case .releaseNotFound:
            return "当前发布源暂无正式 Release。"
        case .httpStatus(403):
            return "GitHub API 访问受限，请稍后重试或打开发布页。"
        case let .httpStatus(statusCode):
            return "更新源返回 HTTP \(statusCode)。"
        case .emptyReleaseFeed:
            return "更新源没有返回可用版本。"
        }
    }
}

struct UpdateCheckHTTPResponse: Equatable, Sendable {
    let statusCode: Int?
}

struct UpdateCheckService: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, UpdateCheckHTTPResponse)

    var dataLoader: DataLoader = Self.defaultDataLoader
    var now: @Sendable () -> Date = { Date() }

    func check(currentVersion: AppVersionInfo = .current) async throws -> UpdateCheckResult {
        guard let updateCheckURL = currentVersion.updateCheckURL else {
            throw UpdateCheckError.missingUpdateURL
        }

        var request = URLRequest(url: updateCheckURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("\(currentVersion.name)/\(currentVersion.displayVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataLoader(request)
        if let statusCode = response.statusCode, (200...299).contains(statusCode) == false {
            if statusCode == 404 {
                throw UpdateCheckError.releaseNotFound
            }
            throw UpdateCheckError.httpStatus(statusCode)
        }

        let latestRelease = try Self.decodeReleaseInfo(from: data)
        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestRelease: latestRelease,
            availability: UpdateAvailability.resolve(
                current: currentVersion.comparableVersion,
                latest: latestRelease.version
            ),
            checkedAt: now()
        )
    }

    private static func defaultDataLoader(_ request: URLRequest) async throws -> (Data, UpdateCheckHTTPResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, UpdateCheckHTTPResponse(statusCode: (response as? HTTPURLResponse)?.statusCode))
    }

    private static func decodeReleaseInfo(from data: Data) throws -> UpdateReleaseInfo {
        let decoder = JSONDecoder()
        if let release = try? decoder.decode(GitHubReleaseResponse.self, from: data) {
            guard release.draft == false, release.prerelease == false else {
                throw UpdateCheckError.emptyReleaseFeed
            }
            return release.info
        }

        let releases = try decoder.decode([GitHubReleaseResponse].self, from: data)
        guard let release = releases.first(where: { $0.draft == false && $0.prerelease == false }) else {
            throw UpdateCheckError.emptyReleaseFeed
        }
        return release.info
    }
}

struct AppSemanticVersion: Comparable, Equatable, Sendable {
    private let components: [Int]
    private let prerelease: [String]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        value = String(value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let versionParts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let numericPart = versionParts.first else {
            return nil
        }

        let parsedComponents = numericPart.split(separator: ".").map { Int($0) }
        guard parsedComponents.isEmpty == false, parsedComponents.allSatisfy({ $0 != nil }) else {
            return nil
        }
        components = parsedComponents.compactMap { $0 }

        if versionParts.count > 1 {
            prerelease = versionParts[1].split(separator: ".").map(String.init)
        } else {
            prerelease = []
        }
    }

    static func == (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        compareComponents(lhs.components, rhs.components) == .orderedSame
            && lhs.prerelease == rhs.prerelease
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        switch compareComponents(lhs.components, rhs.components) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return comparePrerelease(lhs.prerelease, rhs.prerelease)
        }
    }

    private static func compareComponents(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Bool {
        if lhs.isEmpty || rhs.isEmpty {
            return lhs.isEmpty == false && rhs.isEmpty
        }

        for index in 0..<max(lhs.count, rhs.count) {
            if index >= lhs.count {
                return true
            }
            if index >= rhs.count {
                return false
            }
            let left = lhs[index]
            let right = rhs[index]
            if left == right {
                continue
            }
            switch (Int(left), Int(right)) {
            case let (.some(leftNumber), .some(rightNumber)):
                return leftNumber < rightNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.localizedStandardCompare(right) == .orderedAscending
            }
        }
        return false
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let publishedAt: Date?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAssetResponse]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case body
        case draft
        case prerelease
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        publishedAt = Self.parseDate(try container.decodeIfPresent(String.self, forKey: .publishedAt))
        body = try container.decodeIfPresent(String.self, forKey: .body)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([GitHubReleaseAssetResponse].self, forKey: .assets) ?? []
    }

    var info: UpdateReleaseInfo {
        UpdateReleaseInfo(
            tagName: tagName,
            name: name ?? tagName,
            version: Self.version(from: tagName),
            htmlURL: htmlURL,
            publishedAt: publishedAt,
            body: body ?? "",
            assets: assets.map(\.info)
        )
    }

    private static func version(from tagName: String) -> String {
        if tagName.hasPrefix("v") || tagName.hasPrefix("V") {
            return String(tagName.dropFirst())
        }
        return tagName
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct GitHubReleaseAssetResponse: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }

    var info: UpdateReleaseAsset {
        UpdateReleaseAsset(name: name, downloadURL: browserDownloadURL, size: size)
    }
}
