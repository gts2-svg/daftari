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
        .overlay {
            if Store.openError != nil { StoreRecoveryView() }
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
                BackupService.autoBackupIfDue()
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

/// Shown instead of crashing when the saved data can't be opened.
struct StoreRecoveryView: View {
    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40)).foregroundStyle(.orange)
                Text("تعذّر فتح بياناتك").font(.title.bold())
                Text("لا تحذف التطبيق. بياناتك ما زالت محفوظة في الجوال، لكن هذه النسخة ما قدرت تقرأها. احفظ ملفات البيانات تحت في «الملفات»، وأرسلها لي نسترجعها.")
                    .font(.body)
                if !Store.storeFiles.isEmpty {
                    ShareLink(items: Store.storeFiles) {
                        Label("احفظ ملفات البيانات", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding()
                            .background(T.accent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                }
                Text(Store.openError ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(4)
            }
            .padding(24)
        }
    }
}
