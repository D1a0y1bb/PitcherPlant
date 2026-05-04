import Foundation

enum AppLanguageRuntime {
    private static let appleLanguagesKey = "AppleLanguages"

    static func applySavedLanguagePreference(defaults: UserDefaults = .standard) {
        apply(AppPreferences.loadAppSettings(defaults: defaults).language, defaults: defaults)
    }

    static func apply(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        switch language {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        case .zhHans:
            defaults.set(["zh-Hans", "en"], forKey: appleLanguagesKey)
        case .english:
            defaults.set(["en", "zh-Hans"], forKey: appleLanguagesKey)
        }
        defaults.synchronize()
    }
}
