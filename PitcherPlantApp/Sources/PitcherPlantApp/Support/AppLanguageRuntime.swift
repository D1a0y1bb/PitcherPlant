import Foundation
import ObjectiveC.runtime

nonisolated(unsafe) private var sparkleLocalizationContextKey: UInt8 = 0

enum AppLanguageRuntime {
    private static let appleLanguagesKey = "AppleLanguages"
    private static let sparkleBundleIdentifier = "org.sparkle-project.Sparkle"
    private static let sparkleNewerThanLatestKey = "%@ %@ is currently the newest version available.\n(You are currently running version\u{00a0}%@.)"

    static func applySavedLanguagePreference(defaults: UserDefaults = .standard) {
        apply(AppPreferences.loadAppSettings(defaults: defaults).language, defaults: defaults)
    }

    static func apply(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        switch language {
        case .system:
            defaults.removeObject(forKey: appleLanguagesKey)
        case .zhHans:
            defaults.set(["zh_CN", "zh-Hans", "en"], forKey: appleLanguagesKey)
        case .english:
            defaults.set(["en"], forKey: appleLanguagesKey)
        }
        defaults.synchronize()
        if defaults === UserDefaults.standard {
            applySparkleLocalizationOverride(for: language)
        }
    }

    static func sparkleLocalizationResourceName(for language: AppLanguage) -> String {
        switch LocalizationStrings.resolvedLanguage(language) {
        case .zhHans:
            return "zh_CN"
        case .english, .system:
            return "Base"
        }
    }

    static func sparkleLocalizedStringOverride(forKey key: String, language: AppLanguage) -> String? {
        guard key == sparkleNewerThanLatestKey else {
            return nil
        }
        switch LocalizationStrings.resolvedLanguage(language) {
        case .zhHans:
            return "%1$@ %2$@是当前的最新版本。"
        case .english, .system:
            return "%1$@ %2$@ is currently the newest version available."
        }
    }

    private static func applySparkleLocalizationOverride(for language: AppLanguage) {
        guard let sparkleBundle = sparkleBundle() else {
            return
        }
        if object_getClass(sparkleBundle) !== SparkleLocalizedBundle.self {
            object_setClass(sparkleBundle, SparkleLocalizedBundle.self)
        }
        let resourceName = sparkleLocalizationResourceName(for: language)
        let localizedBundle = sparkleBundle.url(forResource: resourceName, withExtension: "lproj")
            .flatMap(Bundle.init(url:))
        objc_setAssociatedObject(
            sparkleBundle,
            &sparkleLocalizationContextKey,
            SparkleLocalizationContext(bundle: localizedBundle, language: language),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    private static func sparkleBundle() -> Bundle? {
        if let bundle = Bundle(identifier: sparkleBundleIdentifier) {
            return bundle
        }
        return Bundle.allFrameworks.first {
            $0.bundleIdentifier == sparkleBundleIdentifier
        }
    }
}

private final class SparkleLocalizationContext: NSObject {
    let bundle: Bundle?
    let language: AppLanguage

    init(bundle: Bundle?, language: AppLanguage) {
        self.bundle = bundle
        self.language = language
    }
}

private final class SparkleLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let context = objc_getAssociatedObject(self, &sparkleLocalizationContextKey) as? SparkleLocalizationContext {
            if let override = AppLanguageRuntime.sparkleLocalizedStringOverride(forKey: key, language: context.language) {
                return override
            }
            if let bundle = context.bundle {
                return bundle.localizedString(forKey: key, value: value, table: tableName)
            }
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
