import SwiftUI
import UserNotifications
import Speech
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.Key.morning) private var morning = 8 * 60
    @AppStorage(Prefs.Key.evening) private var evening = 20 * 60
    @AppStorage(Prefs.Key.hijriPrimary) private var hijriPrimary = true
    @AppStorage(Prefs.Key.useSystemCalendar) private var useSystemCalendar = true
    @AppStorage(Prefs.Key.defaultLead) private var defaultLead = 60
    @AppStorage(Prefs.Key.importReminders) private var importReminders = false
    @State private var remindersNote: String?

    @State private var notifOK = false
    @State private var notifDenied = false
    @State private var timeSensitiveOK = false
    @State private var alarmOK = false
    @State private var calendarOK = false
    @State private var micOK = false
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("رسالة الصباح", selection: timeBinding($morning), displayedComponents: .hourAndMinute)
                    DatePicker("وش صار اليوم؟", selection: timeBinding($evening), displayedComponents: .hourAndMinute)
                } header: {
                    Text("الأوقات اليومية")
                } footer: {
                    Text("إذا ما سجّلت يومك، يذكّرك مرة ثانية بعد ساعة ونص.")
                }

                Section("العرض") {
                    Picker("التقويم الأساسي", selection: $hijriPrimary) {
                        Text("هجري").tag(true)
                        Text("ميلادي").tag(false)
                    }
                    Toggle("أظهر مواعيد تقويم الآيفون", isOn: $useSystemCalendar)
                }

                Section {
                    Toggle("اجلب تذكيرات الآيفون", isOn: $importReminders)
                    if importReminders {
                        Button("اجلبها الحين") { Task { await syncReminders() } }
                    }
                } header: {
                    Text("تذكيرات الآيفون")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("أي تذكير تضيفه في تطبيق التذكيرات أو بسيري ينضاف هنا كل ما تفتح دفتري، ولما تخلّصه هنا يتعلّم «تم» هناك.")
                        if let remindersNote { Text(remindersNote).foregroundStyle(T.accent) }
                    }
                }

                Section {
                    Picker("المنبّه قبل الموعد الضروري", selection: $defaultLead) {
                        Text("وقت الموعد").tag(0)
                        Text("15 دقيقة").tag(15)
                        Text("30 دقيقة").tag(30)
                        Text("ساعة").tag(60)
                        Text("ساعتين").tag(120)
                    }
                    Button("جرّب المنبّه الضروري (بعد دقيقة)") {
                        Task {
                            let ok = await AlarmService.scheduleTest()
                            toast = ok ? "بعد دقيقة يرن المنبّه. اقفل الجوال وانتظر." : "اسمح بالمنبّهات أولاً من الأذونات تحت."
                            await refresh()
                        }
                    }
                    Button("جرّب التنبيه المهم (بعد دقيقة)") {
                        Task {
                            await NotificationFactory.sendTest(sensitive: true)
                            toast = "بعد دقيقة يوصلك التنبيه. اقفل الجوال وانتظر."
                        }
                    }
                } header: {
                    Text("التنبيهات")
                } footer: {
                    if let toast { Text(toast).foregroundStyle(T.accent) }
                }

                Section {
                    permissionRow("الإشعارات", ok: notifOK) { await askNotifications() }
                    if notifOK {
                        permissionRow("التنبيهات المهمة تتجاوز التركيز", ok: timeSensitiveOK) { openSettings() }
                    }
                    permissionRow("المنبّه الحقيقي", ok: alarmOK) {
                        if AlarmService.canAsk { await AlarmService.requestAuthorization() } else { openSettings() }
                    }
                    permissionRow("تقويم الآيفون", ok: calendarOK) {
                        if CalendarService.shared.canAsk { _ = await CalendarService.shared.request() } else { openSettings() }
                        Scheduler.shared.rebuildSoon()
                    }
                    permissionRow("المايك والتعرّف على الكلام", ok: micOK) {
                        _ = await requestSpeechPermissions()
                    }
                } header: {
                    Text("الأذونات")
                } footer: {
                    Text("كل بياناتك محفوظة في جوالك فقط.")
                }

                Section {
                    LabeledContent("الإصدار", value: Self.versionText)
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .task { await refresh() }
            .onChange(of: hijriPrimary) { _, _ in Scheduler.shared.rebuildSoon() }
            .onChange(of: useSystemCalendar) { _, _ in Scheduler.shared.rebuildSoon() }
            .onChange(of: importReminders) { _, on in
                if on { Task { await syncReminders() } }
            }
        }
    }

    /// «0.1.0 · نسخة 4» — the second number goes up with every build.
    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = info["CFBundleShortVersionString"] as? String ?? ""
        let b = info["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) · نسخة \(b)"
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                DF.greg.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60,
                             second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = DF.greg.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                Scheduler.shared.rebuildSoon()
            }
        )
    }

    private func permissionRow(_ title: String, ok: Bool, action: @escaping () async -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if ok {
                Label("مسموح", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.accent)
            } else {
                Button("اسمح") {
                    Task {
                        await action()
                        await refresh()
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func syncReminders() async {
        let service = ReminderService.shared
        if !service.authorized {
            if service.canAsk {
                _ = await service.request()
            } else {
                remindersNote = "اسمح لدفتري بالتذكيرات من إعدادات الآيفون."
                openSettings()
                return
            }
        }
        guard service.authorized else {
            remindersNote = "ما سمحت بالتذكيرات، فما أقدر أجلبها."
            return
        }
        let n = await service.sync()
        Scheduler.shared.rebuildSoon()
        remindersNote = n == 0 ? "ما فيه تذكيرات جديدة." : "انجلب \(n) تذكير."
    }

    private func askNotifications() async {
        if notifDenied {
            openSettings()
        } else {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            Scheduler.shared.rebuildSoon()
        }
    }

    private func refresh() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notifOK = s.authorizationStatus == .authorized
        notifDenied = s.authorizationStatus == .denied
        timeSensitiveOK = s.timeSensitiveSetting == .enabled
        alarmOK = AlarmService.isAuthorized
        calendarOK = CalendarService.shared.authorized
        micOK = SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
