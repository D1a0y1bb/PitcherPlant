import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        AppLanguageRuntime.applySavedLanguagePreference()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    @objc(updater:shouldDownloadReleaseNotesForUpdate:)
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    @objc(versionDisplayerForUpdater:)
    nonisolated func versionDisplayer(for updater: SPUUpdater) -> (any SUVersionDisplay)? {
        appSparkleVersionDisplayer
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    @objc(standardUserDriverRequestsVersionDisplayer)
    nonisolated func standardUserDriverRequestsVersionDisplayer() -> (any SUVersionDisplay)? {
        appSparkleVersionDisplayer
    }

    @objc(standardUserDriverShouldShowVersionHistoryForAppcastItem:)
    nonisolated func standardUserDriverShouldShowVersionHistory(for item: SUAppcastItem) -> Bool {
        false
    }
}

nonisolated(unsafe) private let appSparkleVersionDisplayer = AppSparkleVersionDisplayer()

private final class AppSparkleVersionDisplayer: NSObject, SUVersionDisplay {
    @objc(formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:)
    func formatUpdateVersion(
        fromUpdate update: SUAppcastItem,
        andBundleDisplayVersion inOutBundleDisplayVersion: AutoreleasingUnsafeMutablePointer<NSString>,
        withBundleVersion bundleVersion: String
    ) -> String {
        let bundleDisplayVersion = inOutBundleDisplayVersion.pointee as String
        inOutBundleDisplayVersion.pointee = AppVersionInfo.formattedDisplayVersion(
            bundleDisplayVersion,
            build: bundleVersion
        ) as NSString
        return AppVersionInfo.formattedDisplayVersion(
            update.displayVersionString,
            build: update.versionString
        )
    }

    @objc(formatBundleDisplayVersion:withBundleVersion:matchingUpdate:)
    func formatBundleDisplayVersion(
        _ bundleDisplayVersion: String,
        withBundleVersion bundleVersion: String,
        matchingUpdate: SUAppcastItem?
    ) -> String {
        AppVersionInfo.formattedDisplayVersion(bundleDisplayVersion, build: bundleVersion)
    }
}
