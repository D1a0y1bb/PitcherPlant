import Foundation

enum WorkspacePresentationMode: String, CaseIterable, Identifiable, Sendable {
    case map
    case dashboard

    var id: String { rawValue }

    static func resolved(from rawValue: String) -> WorkspacePresentationMode {
        WorkspacePresentationMode(rawValue: rawValue) ?? .map
    }
}
