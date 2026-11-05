import AppIntents

/// Lets the Action button, Back Tap or Siri jump straight into recording a thought.
struct RecordIdeaIntent: AppIntent {
    static var title: LocalizedStringResource = "فكرة بالصوت"
    static var description = IntentDescription("يفتح دفتري ويبدأ تسجيل فكرة بصوتك.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.open(.voice(.idea))
        return .result()
    }
}

struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "إضافة سريعة"
    static var description = IntentDescription("يفتح دفتري على شاشة الإضافة.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.open(.add(prefill: "", date: nil, kind: nil))
        return .result()
    }
}

struct DaftariShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordIdeaIntent(),
            phrases: ["فكرة جديدة في \(.applicationName)", "سجل فكرة في \(.applicationName)"],
            shortTitle: "فكرة بالصوت",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: QuickAddIntent(),
            phrases: ["أضف في \(.applicationName)"],
            shortTitle: "إضافة سريعة",
            systemImageName: "plus"
        )
    }
}
