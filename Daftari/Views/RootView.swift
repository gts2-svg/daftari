import SwiftUI

struct RootView: View {
    @ObservedObject private var state = AppState.shared
    @Environment(\.scenePhase) private var phase

    var body: some View {
        TabView(selection: $state.tab) {
            TodayView()
                .tabItem { Label("اليوم", systemImage: "sun.max") }
                .tag(0)
            CalendarScreen()
                .tabItem { Label("الجدول", systemImage: "calendar") }
                .tag(1)
            IdeasView()
                .tabItem { Label("الأفكار", systemImage: "lightbulb") }
                .tag(2)
            ThingsView()
                .tabItem { Label("أشيائي", systemImage: "shippingbox") }
                .tag(3)
        }
        .sheet(item: $state.sheet) { route in
            sheetContent(route).daftariEnvironment()
        }
        .fullScreenCover(item: $state.cover) { route in
            coverContent(route).daftariEnvironment()
        }
        .task {
            #if DEBUG
            if Demo.isOn {
                await Demo.run()
                return
            }
            #endif
            await Permissions.firstRun()
            if await ReminderService.shared.sync() > 0 { Scheduler.shared.rebuildSoon() }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await ReminderService.shared.sync()
                    Scheduler.shared.rebuildSoon()
                }
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: Route) -> some View {
        switch route {
        case .add(let prefill, let date, let kind):
            AddSheet(prefill: prefill, presetDate: date, presetKind: kind)
        case .edit(let uid):
            AddSheet(editingUID: uid)
        case .convert(let uid):
            AddSheet(convertUID: uid)
        case .evening:
            EveningCheckView()
        case .morning:
            MorningBriefView()
        case .settings:
            SettingsView()
        case .medicine(let uid):
            MedicineSheet(editingUID: uid)
        case .voice, .urgent:
            EmptyView()
        }
    }

    @ViewBuilder
    private func coverContent(_ route: Route) -> some View {
        switch route {
        case .voice(let mode):
            VoiceCaptureView(mode: mode)
        case .urgent(let uid):
            UrgentView(uid: uid)
        default:
            EmptyView()
        }
    }
}
