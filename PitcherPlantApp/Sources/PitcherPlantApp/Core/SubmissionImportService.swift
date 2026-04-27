import Foundation
import ZIPFoundation

struct SubmissionImportOptions: Hashable, Sendable {
    var maxNestedZipDepth: Int = 2
    var ignoredNames: Set<String> = [".DS_Store", "__MACOSX"]
    var allowedExtensions: Set<String> = DocumentIngestionService.supportedExtensions.union(["zip"])
}

struct SubmissionImportIssue: Codable, Hashable, Sendable {
    enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    let path: String
    let severity: Severity
    let message: String
}

struct SubmissionImportResult: Hashable, Sendable {
    let batch: SubmissionBatch
    let items: [SubmissionItem]
    let issues: [SubmissionImportIssue]
}

struct SubmissionImportService {
    func importPackage(
        at sourceURL: URL,
        into supportDirectory: URL,
        options: SubmissionImportOptions = SubmissionImportOptions()
    ) throws -> SubmissionImportResult {
        let batchID = UUID()
        let batchName = sourceURL.deletingPathExtension().lastPathComponent
        let destination = supportDirectory
            .appendingPathComponent("submission-imports", isDirectory: true)
            .appendingPathComponent(batchID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        var issues: [SubmissionImportIssue] = []
        let importRoot: URL
        if sourceURL.pathExtension.lowercased() == "zip" {
            importRoot = destination.appendingPathComponent("expanded", isDirectory: true)
            try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
            try extractZip(sourceURL, to: importRoot, depth: 0, options: options, issues: &issues)
        } else {
            importRoot = sourceURL
        }

        let items = buildItems(batchID: batchID, importRoot: importRoot, options: options, issues: &issues)
        let batch = SubmissionBatch(
            id: batchID,
            name: batchName,
            sourcePath: sourceURL.path,
            destinationPath: importRoot.path,
            itemCount: items.count
        )
        return SubmissionImportResult(batch: batch, items: items, issues: issues)
    }

    func auditJobs(from result: SubmissionImportResult, outputDirectory: URL, template: String) -> [AuditJob] {
        result.items.map { item in
            var configuration = AuditConfiguration.defaults(for: outputDirectory.deletingLastPathComponent())
            configuration.directoryPath = item.rootPath
            configuration.outputDirectoryPath = outputDirectory.path
            configuration.reportNameTemplate = template
                .replacingOccurrences(of: "{team}", with: item.teamName)
            var job = AuditJob(configuration: configuration)
            job.batchID = result.batch.id
            job.submissionItemID = item.id
            return job
        }
    }

    private func extractZip(
        _ url: URL,
        to destination: URL,
        depth: Int,
        options: SubmissionImportOptions,
        issues: inout [SubmissionImportIssue]
    ) throws {
        guard depth <= options.maxNestedZipDepth else {
            issues.append(SubmissionImportIssue(path: url.path, severity: .warning, message: "嵌套 ZIP 深度超过限制"))
            return
        }
        let archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        for entry in archive {
            guard shouldKeep(entry.path, options: options) else {
                continue
            }
            guard let targetURL = safeDestination(for: entry.path, base: destination) else {
                issues.append(SubmissionImportIssue(path: entry.path, severity: .error, message: "路径穿越已拦截"))
                continue
            }

            switch entry.type {
            case .directory:
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            case .file:
                try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                var data = Data()
                _ = try archive.extract(entry) { part in data.append(part) }
                try data.write(to: targetURL, options: .atomic)
                if targetURL.pathExtension.lowercased() == "zip" {
                    let nestedDestination = targetURL.deletingPathExtension()
                    try FileManager.default.createDirectory(at: nestedDestination, withIntermediateDirectories: true)
                    try extractZip(targetURL, to: nestedDestination, depth: depth + 1, options: options, issues: &issues)
                }
            case .symlink:
                issues.append(SubmissionImportIssue(path: entry.path, severity: .warning, message: "符号链接已跳过"))
            }
        }
    }

    private func buildItems(
        batchID: UUID,
        importRoot: URL,
        options: SubmissionImportOptions,
        issues: inout [SubmissionImportIssue]
    ) -> [SubmissionItem] {
        let fileManager = FileManager.default
        let children = (try? fileManager.contentsOfDirectory(at: importRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let directoryChildren = children.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && options.ignoredNames.contains(url.lastPathComponent) == false
        }
        let roots = directoryChildren.isEmpty ? [importRoot] : directoryChildren

        return roots.map { root in
            let files = collectFiles(in: root, options: options)
            let ignoredCount = files.ignored
            if files.accepted.isEmpty {
                issues.append(SubmissionImportIssue(path: root.path, severity: .warning, message: "未发现可审计文件"))
            }
            return SubmissionItem(
                batchID: batchID,
                teamName: inferTeamName(from: root),
                rootPath: root.path,
                fileCount: files.accepted.count,
                ignoredCount: ignoredCount,
                problemCount: files.accepted.isEmpty ? 1 : 0
            )
        }
    }

    private func collectFiles(in root: URL, options: SubmissionImportOptions) -> (accepted: [URL], ignored: Int) {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var accepted: [URL] = []
        var ignored = 0
        while let url = enumerator?.nextObject() as? URL {
            if options.ignoredNames.contains(url.lastPathComponent) {
                ignored += 1
                continue
            }
            let ext = url.pathExtension.lowercased()
            if options.allowedExtensions.contains(ext) {
                accepted.append(url)
            } else if ext.isEmpty == false {
                ignored += 1
            }
        }
        return (accepted, ignored)
    }

    private func shouldKeep(_ path: String, options: SubmissionImportOptions) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        return parts.contains { options.ignoredNames.contains($0) } == false
    }

    private func safeDestination(for entryPath: String, base: URL) -> URL? {
        let target = base.appendingPathComponent(entryPath).standardizedFileURL
        let basePath = base.standardizedFileURL.path
        guard target.path == basePath || target.path.hasPrefix(basePath + "/") else {
            return nil
        }
        return target
    }

    private func inferTeamName(from root: URL) -> String {
        let name = root.lastPathComponent
            .replacingOccurrences(of: #"^\d+[-_\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名队伍" : name
    }
}
