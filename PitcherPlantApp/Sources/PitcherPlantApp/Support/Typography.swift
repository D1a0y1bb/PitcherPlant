import SwiftUI

enum AppTypography {
    static let pageTitle: Font = .title2.weight(.semibold)
    static let sectionTitle: Font = .headline
    static let rowPrimary: Font = .body.weight(.medium)
    static let rowSecondary: Font = .callout
    static let body: Font = .body
    static let supporting: Font = .callout
    static let metadata: Font = .footnote
    static let tableHeader: Font = .footnote.weight(.semibold)
    static let badge: Font = .footnote.weight(.semibold)
    static let code: Font = .system(.callout, design: .monospaced)
    static let smallCode: Font = .system(.footnote, design: .monospaced)
}
