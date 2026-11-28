import BackgroundTasks
import Foundation

// iOS decides when a refresh is delivered. The Shortcut has already stored the event.
enum FinamiCaptureBackground {
    static let identifier = "ua.finora.personal.capture-refresh"
    static func schedule() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--finami-qa") { return }
        #endif
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request); UserDefaults.standard.set("requested", forKey: "finami.backgroundCaptureSchedule") }
        catch { UserDefaults.standard.set("unavailable", forKey: "finami.backgroundCaptureSchedule") }
    }
    @MainActor static func process(store: Store) async {
        schedule()
        guard !Task.isCancelled else { return }
        await store.loadDatabase()
        guard !Task.isCancelled, store.storageHealthy, !store.loading else { return }
        await store.refreshCapturesInBackground()
        guard !Task.isCancelled else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "finami.lastBackgroundCapture")
    }
}
