import Foundation
@testable import PitcherPlantApp

func testWorkspaceRoot() throws -> URL {
    var candidate = URL(fileURLWithPath: #filePath)
    for _ in 0..<12 {
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Fixtures/WriteupSamples/date").path) {
            return candidate
        }
        candidate.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}
