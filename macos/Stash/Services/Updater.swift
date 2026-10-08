import Foundation
import Observation
import Sparkle

/// Checks for new versions with Sparkle: once a day on its own, or from
/// Stash › Check for Updates…. The feed URL and the public signing key are in
/// Stash-Info.plist; releases are published by scripts/release-mac.sh.
@Observable
final class Updater {
    /// False while a check is already running.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: !StashApp.isHostingTests,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            guard let self else { return }
            let canCheck = updater.canCheckForUpdates
            Task { @MainActor in self.canCheckForUpdates = canCheck }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
