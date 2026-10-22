import ServiceManagement
import Combine

@MainActor
final class LoginItemManager: ObservableObject {
    @Published var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail if the app isn't running from a stable,
            // bundled location (e.g. a loose debug binary from `swift run`).
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
