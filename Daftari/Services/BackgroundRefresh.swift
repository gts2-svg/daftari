import Foundation
import BackgroundTasks

/// Asks iOS to wake دفتري now and then in the background to renew the reminder schedule,
/// so reminders keep coming even if the app isn't opened for days. iOS decides when (not
/// guaranteed), which is why the scheduler also leaves a «افتح دفتري» note at the end.
enum BackgroundRefresh {
    static let id = "com.gts2svg.daftari.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task { @MainActor in
                await Scheduler.shared.rebuild()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: id)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
