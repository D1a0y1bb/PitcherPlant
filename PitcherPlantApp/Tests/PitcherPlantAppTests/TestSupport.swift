import Foundation
@testable import PitcherPlantApp

func testRepositoryRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<12 {
        let releaseWorkflow = candidate.appendingPathComponent(".github/workflows/release.yml")
        let packageManifest = candidate.appendingPathComponent("PitcherPlantApp/Package.swift")
        if FileManager.default.fileExists(atPath: releaseWorkflow.path),
           FileManager.default.fileExists(atPath: packageManifest.path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}
