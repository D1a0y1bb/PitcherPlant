import Foundation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .zhHans: return "简体中文"
        case .english: return "English"
        }
    }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var language: AppLanguage
    var appearance: AppAppearance
    var showInspectorByDefault: Bool
    var compactRows: Bool
    var showMenuBarExtra: Bool
    var preferInAppReports: Bool
    var defaultExportFormat: ExportRecord.Format
    var showAttachmentPreviews: Bool
    var auditAssistant: AuditAssistantConfiguration? = AuditAssistantConfiguration()

    static let defaults = AppSettings(
        language: .system,
        appearance: .system,
        showInspectorByDefault: true,
        compactRows: true,
        showMenuBarExtra: true,
        preferInAppReports: true,
        defaultExportFormat: .html,
        showAttachmentPreviews: true,
        auditAssistant: AuditAssistantConfiguration()
    )
}
