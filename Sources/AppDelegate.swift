//
//  AppDelegate.swift
//  Nudge
//
//  Main application delegate — owns the HUD panel, timers, schedule state,
//  and minimized-mode UI. Expanded-mode UI lives in AppDelegate+Expanded.swift.
//

import Cocoa
import UserNotifications
import Sparkle

/// Tiny shared object that NSButton can target for the mood-picker buttons
/// in the weekly reflection prompt. NSAlert accessory views can't easily own
/// closures, so this bridges via an @objc selector.
@MainActor
final class MoodPickerHandler: NSObject {
    static let shared = MoodPickerHandler()
    var onPick: ((Int) -> Void)?
    @objc func pick(_ sender: NSButton) {
        onPick?(sender.tag)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Sparkle auto-updater
    var updaterController: SPUStandardUpdaterController!

    // MARK: - Window + key views

    var panel: HUDPanel!
    var contentView: HUDContentView!
    var visualEffect: NSVisualEffectView!
    var borderLayer: CALayer!

    // MARK: - Minimized labels & controls

    let clockLabel       = NSTextField(labelWithString: "")
    let nowHeaderLabel   = NSTextField(labelWithString: "NOW")
    let currentTaskLabel = NSTextField(labelWithString: "")
    let countdownLabel   = NSTextField(labelWithString: "")
    let progressBar      = NSView()
    let progressFill     = NSView()
    let markDoneButton     = PillButton()
    let markPrevDoneButton = PillButton()
    let expandButton       = NSButton(title: "⤢", target: nil, action: nil)
    let nextHeaderLabel    = NSTextField(labelWithString: "NEXT")
    let nextTaskLabel      = NSTextField(labelWithString: "")
    let progressDotsRow    = NSStackView()
    let progressSummary    = NSTextField(labelWithString: "")
    let dreamsQuoteLabel   = NSTextField(labelWithString: "")
    var dragHandle: DragHandleView!
    var minimizedMainStack: NSStackView?
    /// The container for todo-mode minimized rows (rebuilt on each tick).
    var todosMiniContainer: NSStackView?
    /// Greeting label used in todos minimized mode.
    let todosMiniGreeting = NSTextField(labelWithString: "")
    /// The todo currently being shown in minimized detail view (nil = list mode).
    var miniDetailTodoId: String? = nil
    /// Whether the quick-add text field is currently visible in todos minimized mode.
    var isQuickAddActive: Bool = false
    /// The quick-add text field shown in the minimized view.
    var quickAddField: NSTextField?
    /// "Quick Add To-Do" button in the todos minimized view.
    let quickAddBtn = NSButton(title: "", target: nil, action: nil)
    /// Cached known-good minimized panel height. Recomputed only when
    /// the panel is actually in minimized mode (never during expand).
    var cachedMinimizedHeight: CGFloat = 0

    // MARK: - Expanded-mode state
    // (stored properties must live on the class — extensions cannot add them.
    //  The methods that manipulate them live in AppDelegate+Expanded.swift.)

    var isExpanded: Bool = false
    var minimizedFrame: NSRect = .zero
    var minimizedContentRoot: NSView?
    var expandedContentRoot: NSView?
    var expandedSection: ExpandedSection = .today
    var expandedMainArea: NSView?
    var expandedDragStrip: DragHandleView?
    var expandedTaglineLabel: NSTextField?
    var sidebarButtons: [ExpandedSection: NSButton] = [:]
    var lastRenderedExpandedBlockIndex: Int? = nil
    var scheduleSelectedWeekday: Int = Calendar.current.component(.weekday, from: Date())
    var scheduleDayButtons: [Int: NSButton] = [:]
    var scheduleListContainer: NSView?

    /// Calendar-week schedule view state. Stores the Monday of the
    /// currently-viewed week so we can navigate by week with the chevrons.
    var scheduleViewedWeekStart: Date = AppDelegate.mondayOfWeek(containing: Date())
    /// Optional — only set when the user explicitly tapped a day or when
    /// the viewed week IS the current week (default to today).
    /// `nil` means "no day highlighted in this week".
    var scheduleSelectedDate: Date? = Calendar.current.startOfDay(for: Date())
    var weekPickerPanel: NSPanel?

    /// Drill-down state for the calendar picker popup.
    enum CalendarPickerStep { case year, month, day }
    var pickerStep: CalendarPickerStep = .month
    var pickerYear: Int = Calendar.current.component(.year, from: Date())
    var pickerMonth: Int = Calendar.current.component(.month, from: Date())
    /// Cursor inside the day grid for keyboard navigation. Day-of-month.
    var pickerCursorDay: Int = Calendar.current.component(.day, from: Date())
    /// Local NSEvent monitor for picker keyboard nav; cleared on dismiss.
    var pickerKeyMonitor: Any?

    /// Light-mood theme toggle. When on, the HUD uses a lighter visual
    /// effect material so the panel feels brighter / less moody.
    /// Persisted across launches.
    var lightMoodEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "Nudge.lightMood") }
        set { UserDefaults.standard.set(newValue, forKey: "Nudge.lightMood") }
    }

    // MARK: - User Settings (onboarding + personalization)

    /// The user's first name, collected during onboarding.
    var userName: String = ""
    /// Whether the first-launch onboarding has been completed.
    var hasCompletedOnboarding: Bool = false
    /// Which layout to show in the minimized HUD: "schedule" or "todos".
    var minimizedViewMode: String = "schedule"
    /// Whether hourly water reminders are active. Off by default.
    var waterRemindersEnabled: Bool = false
    /// Whether 20-20-20 eye break reminders are active. Off by default.
    var eyeBreakEnabled: Bool = false
    /// When true, the panel doesn't auto-snap to corners after dragging.
    var snapToCornerDisabled: Bool = false

    func loadUserSettings() {
        userName = UserDefaults.standard.string(forKey: "Nudge.userName") ?? ""
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "Nudge.hasCompletedOnboarding")
        minimizedViewMode = UserDefaults.standard.string(forKey: "Nudge.minimizedViewMode") ?? "schedule"
        waterRemindersEnabled = UserDefaults.standard.bool(forKey: "Nudge.waterRemindersEnabled")
        eyeBreakEnabled = UserDefaults.standard.bool(forKey: "Nudge.eyeBreakEnabled")
        snapToCornerDisabled = UserDefaults.standard.bool(forKey: "Nudge.snapToCornerDisabled")
    }
    func saveUserName(_ name: String) {
        userName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(userName, forKey: "Nudge.userName")
    }
    func saveMinimizedViewMode(_ mode: String) {
        minimizedViewMode = mode
        UserDefaults.standard.set(mode, forKey: "Nudge.minimizedViewMode")
    }
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "Nudge.hasCompletedOnboarding")
    }

    // MARK: - Backlog
    // Items left undone when a day rolls over. Persisted by date+blockKey
    // so we can show "what slipped through" and let the user catch up.

    struct BacklogItem: Codable, Equatable {
        var dateKey: String   // original day the block came from
        var blockKey: String  // start-end-name (matches doneState keys)
        var name: String
        var startStr: String  // "HH:mm" for display
        var endStr: String
    }

    var backlog: [BacklogItem] = []
    static let backlogKey = "Nudge.backlog"
    /// Lifetime count of backlog items the user has explicitly marked done.
    var backlogDoneCount: Int {
        get { UserDefaults.standard.integer(forKey: "Nudge.backlogDoneCount") }
        set { UserDefaults.standard.set(newValue, forKey: "Nudge.backlogDoneCount") }
    }

    func loadBacklog() {
        if let data = UserDefaults.standard.data(forKey: Self.backlogKey),
           let decoded = try? JSONDecoder().decode([BacklogItem].self, from: data) {
            backlog = decoded
        }
    }
    func saveBacklog() {
        if let data = try? JSONEncoder().encode(backlog) {
            UserDefaults.standard.set(data, forKey: Self.backlogKey)
        }
    }

    /// Walk back through dates Nudge has actually seen running and add
    /// anything completable that wasn't marked done to the backlog.
    /// Idempotent — won't add duplicates. Bounded by:
    ///   - the earliest day Nudge has ever recorded as running
    ///     (UserDefaults "Nudge.firstRunDate")
    ///   - the day before today (we never backlog blocks for today itself,
    ///     since the day hasn't ended yet)
    func sweepBacklogForOverdueDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Establish / read the first-run anchor.
        let firstRunKey = "Nudge.firstRunDate"
        let firstRunDate: Date
        if let stored = UserDefaults.standard.string(forKey: firstRunKey),
           let d = AppDelegate.parseDateKey(stored) {
            firstRunDate = d
        } else {
            // First time we've ever swept — anchor to today and exit. We have
            // nothing to backlog because we don't know what days were "missed"
            // before Nudge existed on this Mac.
            UserDefaults.standard.set(todayKey(today), forKey: firstRunKey)
            // Wipe any pre-existing backlog from before this anchor existed
            // (the previous version of the sweep over-eagerly added 14 days
            // of bogus items).
            if !backlog.isEmpty {
                backlog.removeAll()
                saveBacklog()
            }
            return
        }

        // Only consider days strictly before today AND on/after firstRunDate.
        let earliest = max(firstRunDate, cal.date(byAdding: .day, value: -60, to: today) ?? firstRunDate)
        guard earliest < today else { return }

        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        var added = false
        var cursor = earliest
        while cursor < today {
            let dk = todayKey(cursor)
            let blocks = todaysSchedule(for: cursor).filter { isCompletable($0) }
            let doneSet = doneState[dk] ?? []
            for b in blocks where !doneSet.contains(blockKey(b)) {
                let bk = blockKey(b)
                if backlog.contains(where: { $0.dateKey == dk && $0.blockKey == bk }) {
                    continue
                }
                let removedKey = "Nudge.backlogRemoved.\(dk).\(bk)"
                if UserDefaults.standard.bool(forKey: removedKey) {
                    continue
                }
                backlog.append(BacklogItem(
                    dateKey: dk,
                    blockKey: bk,
                    name: b.name,
                    startStr: f.string(from: b.start),
                    endStr: f.string(from: b.end)))
                added = true
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if added { saveBacklog() }
    }

    func backlogMarkDone(_ item: BacklogItem) {
        // Remove from backlog list and bump the lifetime counter.
        backlog.removeAll { $0 == item }
        backlogDoneCount += 1
        saveBacklog()
    }

    func backlogRemove(_ item: BacklogItem) {
        // Soft-delete: also write a "removed" flag so the next sweep
        // doesn't re-add the same item.
        backlog.removeAll { $0 == item }
        let removedKey = "Nudge.backlogRemoved.\(item.dateKey).\(item.blockKey)"
        UserDefaults.standard.set(true, forKey: removedKey)
        saveBacklog()
    }

    // MARK: - Weekly reflection journal
    // weekKey ("yyyy-Www" e.g. "2026-W14") → (mood emoji, note)

    struct WeeklyReflection: Codable {
        var mood: String   // one of 😞 😐 🙂 🤩
        var note: String
    }
    var weeklyReflections: [String: WeeklyReflection] = [:]
    static let weeklyReflectionsKey = "Nudge.weeklyReflections"

    /// Ambient mode — true when the foreground app's window is fullscreen
    /// and we should shrink the HUD to a tiny corner pill.
    var isAmbientMode: Bool = false
    var ambientPillRoot: NSView?

    func loadWeeklyReflections() {
        if let data = UserDefaults.standard.data(forKey: Self.weeklyReflectionsKey),
           let decoded = try? JSONDecoder().decode([String: WeeklyReflection].self, from: data) {
            weeklyReflections = decoded
        }
    }
    func saveWeeklyReflections() {
        if let data = try? JSONEncoder().encode(weeklyReflections) {
            UserDefaults.standard.set(data, forKey: Self.weeklyReflectionsKey)
        }
    }
    static func weekKey(for date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return "\(year)-W\(String(format: "%02d", week))"
    }
    func reflection(for date: Date = Date()) -> WeeklyReflection? {
        return weeklyReflections[Self.weekKey(for: date)]
    }
    func setReflection(_ r: WeeklyReflection, for date: Date = Date()) {
        weeklyReflections[Self.weekKey(for: date)] = r
        saveWeeklyReflections()
    }
    /// Returns true if it's Sunday after 19:00 and we haven't already
    /// recorded a reflection (or shown the prompt) for this week.
    func shouldPromptForWeeklyReflection() -> Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)  // Sunday = 1
        let hour = cal.component(.hour, from: now)
        guard weekday == 1 && hour >= 19 else { return false }
        if reflection(for: now) != nil { return false }
        let dismissedKey = "Nudge.reflectionDismissed.\(Self.weekKey(for: now))"
        return !UserDefaults.standard.bool(forKey: dismissedKey)
    }
    func dismissReflectionPromptForThisWeek() {
        let key = "Nudge.reflectionDismissed.\(Self.weekKey(for: Date()))"
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Modal prompt for the Sunday-evening weekly reflection.
    func showWeeklyReflectionPrompt() {
        let alert = NSAlert()
        alert.messageText = "How did this week feel?"
        alert.informativeText = "Pick a mood, drop a one-line note. Future-\(userName) will thank you."
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        container.frame = NSRect(x: 0, y: 0, width: 360, height: 80)

        let moodRow = NSStackView()
        moodRow.orientation = .horizontal
        moodRow.spacing = 12
        let moods = ["😞", "😐", "🙂", "🤩"]
        var moodButtons: [NSButton] = []
        for emoji in moods {
            let b = NSButton(title: emoji, target: nil, action: nil)
            b.bezelStyle = .inline
            b.isBordered = false
            b.attributedTitle = NSAttributedString(
                string: emoji,
                attributes: [.font: NSFont.systemFont(ofSize: 28)])
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 44).isActive = true
            b.heightAnchor.constraint(equalToConstant: 44).isActive = true
            moodButtons.append(b)
            moodRow.addArrangedSubview(b)
        }
        var pickedMood: String = "🙂"
        for (i, b) in moodButtons.enumerated() {
            b.target = MoodPickerHandler.shared
            b.action = #selector(MoodPickerHandler.pick(_:))
            b.tag = i
        }
        MoodPickerHandler.shared.onPick = { idx in
            pickedMood = moods[idx]
            for (i, b) in moodButtons.enumerated() {
                b.layer?.backgroundColor = (i == idx)
                    ? NSColor.systemBlue.withAlphaComponent(0.30).cgColor
                    : NSColor.clear.cgColor
                b.wantsLayer = true
                b.layer?.cornerRadius = 8
            }
        }
        // Pre-pick happy.
        MoodPickerHandler.shared.onPick?(2)

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "One line on the week…"

        container.addArrangedSubview(moodRow)
        container.addArrangedSubview(field)
        field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        moodRow.widthAnchor.constraint(equalToConstant: 360).isActive = true

        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Maybe later")
        if let win = alert.window as? NSPanel {
            win.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 3)
        }
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        let resp = alert.runModal()
        panel.allowsKey = false

        switch resp {
        case .alertFirstButtonReturn:
            setReflection(WeeklyReflection(mood: pickedMood, note: field.stringValue))
        case .alertSecondButtonReturn:
            dismissReflectionPromptForThisWeek()
        default: break
        }
    }

    /// Returns the Monday of the calendar week containing `date`.
    /// Walks backwards from `date` until we hit a Monday — avoids the
    /// week-of-year + firstWeekday interaction quirks that can land on
    /// the wrong Monday near year boundaries or with non-Mon locales.
    static func mondayOfWeek(containing date: Date) -> Date {
        let cal = Calendar.current
        var d = cal.startOfDay(for: date)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat. Days back to the previous Monday:
        // Sun → 6, Mon → 0, Tue → 1, ..., Sat → 5.
        let wd = cal.component(.weekday, from: d)
        let daysBack = (wd == 1) ? 6 : (wd - 2)
        if daysBack > 0 {
            d = cal.date(byAdding: .day, value: -daysBack, to: d) ?? d
        }
        return d
    }

    // Schedule editor state — methods live in AppDelegate+ScheduleEditor.swift
    enum ScheduleEditorTab { case oneoff, permanent }
    var isEditingSchedule: Bool = false
    var editorTab: ScheduleEditorTab = .oneoff
    var editorWeekday: Int = Calendar.current.component(.weekday, from: Date())
    var editorBlocks: [EditableBlock] = []
    var editorBaseline: [EditableBlock] = []
    var editorRowsContainer: NSView?
    var editorErrorLabel: NSTextField?
    var editorTabButtons: [ScheduleEditorTab: NSButton] = [:]
    var editorDayButtons: [Int: NSButton] = [:]
    var editorOverrideBadge: NSTextField?
    var editorStatusClearTimer: Timer?
    var editorCancelButton: NSButton?

    /// Live label for the 20-20-20 countdown — shown on the Progress page,
    /// updated by tick() once a second so it actually counts down.
    var eyeBreakCountdownLabel: NSTextField?

    /// Live label for the water reminder countdown — also on Progress.
    var waterCountdownLabel: NSTextField?

    /// Custom instructions floating panel — built lazily on first show.
    var instructionsPanel: NSPanel?

    /// First-launch onboarding panel.
    var onboardingPanel: NSPanel?

    enum ExpandedSection { case today, schedule, week, todo, backlog, more }

    // MARK: - Todos

    struct TodoItem: Codable, Equatable {
        var id: String
        var text: String
        var desc: String        // optional longer description
        var priority: Int       // 1=urgent(red) 2=high(orange) 3=medium(blue) 4=none
        var dueDate: Date?
        var createdAt: Date

        init(text: String, desc: String = "", priority: Int = 4, dueDate: Date? = nil) {
            self.id = UUID().uuidString
            self.text = text
            self.desc = desc
            self.priority = max(1, min(4, priority))
            self.dueDate = dueDate
            self.createdAt = Date()
        }

        // Migration: items saved before the `desc` field was added will
        // decode with an empty string via init(from:).
        enum CodingKeys: String, CodingKey {
            case id, text, desc, priority, dueDate, createdAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id        = try c.decode(String.self, forKey: .id)
            text      = try c.decode(String.self, forKey: .text)
            desc      = (try? c.decode(String.self, forKey: .desc)) ?? ""
            priority  = try c.decode(Int.self, forKey: .priority)
            dueDate   = try c.decodeIfPresent(Date.self, forKey: .dueDate)
            createdAt = try c.decode(Date.self, forKey: .createdAt)
        }
    }

    var todos: [TodoItem] = []
    static let todosKey = "Nudge.todos"
    var todoInputField: NSTextField?
    var todoDescField: NSTextField?
    var todoSelectedPriority: Int = 4
    var todoSelectedDueDate: Date? = nil

    // Todo calendar picker state
    var todoCalendarPanel: NSPanel?
    var todoCalPickerYear: Int = Calendar.current.component(.year, from: Date())
    var todoCalPickerMonth: Int = Calendar.current.component(.month, from: Date())
    /// Whether the calendar is picking a date for a new task (true) or
    /// editing an existing task (false). Set before showing the panel.
    var todoCalPickerIsForNew: Bool = true
    /// The ID of the todo being edited via the calendar, if any.
    var todoCalEditingId: String? = nil

    func loadTodos() {
        guard let data = UserDefaults.standard.data(forKey: Self.todosKey) else { return }
        // New TodoItem format (with or without desc field — init(from:) handles both)
        if let items = try? JSONDecoder().decode([TodoItem].self, from: data) {
            todos = items
            return
        }
        // Migrate from old [String] format
        if let strings = try? JSONDecoder().decode([String].self, from: data) {
            todos = strings.map { TodoItem(text: $0) }
            saveTodos()
        }
    }
    func saveTodos() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: Self.todosKey)
        }
    }

    // MARK: - Block notes
    // dateKey ("yyyy-MM-dd") → [blockKey: noteString]
    // One-line notes attached to a specific block on a specific day.

    var blockNotes: [String: [String: String]] = [:]
    static let blockNotesKey = "Nudge.blockNotes"

    func loadBlockNotes() {
        if let data = UserDefaults.standard.data(forKey: Self.blockNotesKey),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            blockNotes = decoded
        }
    }
    func saveBlockNotes() {
        if let data = try? JSONEncoder().encode(blockNotes) {
            UserDefaults.standard.set(data, forKey: Self.blockNotesKey)
        }
    }
    func noteFor(_ b: ScheduleBlock, on day: Date = Date()) -> String? {
        let n = blockNotes[todayKey(day)]?[blockKey(b)]
        return (n?.isEmpty == false) ? n : nil
    }
    func setNote(_ note: String, for b: ScheduleBlock, on day: Date = Date()) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let dk = todayKey(day)
        var dayNotes = blockNotes[dk] ?? [:]
        let bk = blockKey(b)
        if trimmed.isEmpty {
            dayNotes.removeValue(forKey: bk)
        } else {
            dayNotes[bk] = trimmed
        }
        if dayNotes.isEmpty {
            blockNotes.removeValue(forKey: dk)
        } else {
            blockNotes[dk] = dayNotes
        }
        saveBlockNotes()
    }

    // MARK: - Done-state persistence
    // dateKey ("yyyy-MM-dd") → set of block keys

    var doneState: [String: Set<String>] = [:]
    static let doneStateKey = "Nudge.doneState"

    func loadDoneState() {
        guard let data = UserDefaults.standard.data(forKey: Self.doneStateKey),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        doneState = raw.mapValues { Set($0) }
    }
    func saveDoneState() {
        let raw = doneState.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: Self.doneStateKey)
        }
    }
    func todayKey(_ day: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: day)
    }
    func blockKey(_ b: ScheduleBlock) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: b.start))-\(f.string(from: b.end))-\(b.name)"
    }
    func isDone(_ b: ScheduleBlock, on day: Date = Date()) -> Bool {
        return doneState[todayKey(day)]?.contains(blockKey(b)) ?? false
    }
    func setDone(_ b: ScheduleBlock, _ done: Bool, on day: Date = Date()) {
        let dk = todayKey(day)
        var set = doneState[dk] ?? []
        let bk = blockKey(b)
        if done { set.insert(bk) } else { set.remove(bk) }
        doneState[dk] = set
        saveDoneState()
    }
    func isCompletable(_ b: ScheduleBlock) -> Bool {
        // Sourced from EditableBlock.compulsory at conversion time. Old data
        // without an explicit value falls back to the historical name-based
        // default (Break / Sleep non-compulsory, everything else compulsory).
        return b.compulsory
    }
    func previousCompletableIndex(before idx: Int) -> Int? {
        var i = idx - 1
        while i >= 0 {
            if isCompletable(todayBlocks[i]) { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Timers / schedule state

    private var tickTimer: Timer?
    private var dayCheckTimer: Timer?
    private var lastDayCheck = Calendar.current.startOfDay(for: Date())
    /// Tick counter used to throttle the expensive CGWindowList fullscreen
    /// check to once every 5 seconds instead of every tick.
    private var fullscreenCheckCounter: Int = 0
    var currentBlockIndex: Int? = nil
    var todayBlocks: [ScheduleBlock] = []

    // Border pulse animation state
    enum PulseState { case none, amber, red }
    private var pulseState: PulseState = .none

    // Quit hold state (legacy Option+click 3s gesture — kept for safety)
    private var quitHoldTimer: Timer?
    private var quitHoldStart: Date?
    private var quitHoldMonitor: Any?

    // 20-20-20 eye-break state
    var laptopOpenSeconds: Int = 0
    private var screensAsleep: Bool = false
    var isInEyeBreak: Bool = false
    private var eyeBreakRoot: NSView?
    private var preBreakFrame: NSRect = .zero
    static let eyeBreakIntervalSeconds = 20 * 60
    /// Number of times the user has snoozed the CURRENT pending eye break.
    /// Resets each time a new break starts.
    var eyeBreakSnoozesUsed: Int = 0
    static let maxEyeBreakSnoozes = 5
    static let eyeBreakSnoozeSeconds = 2 * 60
    /// Holds the snooze button so we can refresh its label after each tap.
    var eyeBreakSnoozeButton: NSButton?

    // ── Water reminder state ────────────────────────────────────────
    /// Wall-clock time at which the next water reminder should fire. This is
    /// the source of truth — reminders are scheduled, NOT based on elapsed
    /// laptop-open seconds. Persisted in UserDefaults so it survives quits.
    /// Anchor day starts at 7:10 AM; subsequent reminders re-anchor to
    /// `dismissalTime + 1 hour` whenever the user hits Done.
    var nextWaterReminderAt: Date = Date()
    /// How many water reminders the user has dismissed today. Drives the
    /// "drink half" vs "drink the other half + refill" alternation. Resets
    /// every new calendar day. Persisted alongside the anchor.
    var waterRemindersFired: Int = 0
    /// Whether the water-break modal overlay is currently showing.
    var isInWaterBreak: Bool = false
    private var waterBreakRoot: NSView?
    private var waterBreakLabel: NSTextField?
    var waterBreakSnoozeButton: NSButton?
    /// Snoozes used for the CURRENT pending water break. Resets each new break.
    var waterBreakSnoozesUsed: Int = 0
    static let maxWaterBreakSnoozes = 3
    static let waterBreakSnoozeSeconds = 5 * 60
    static let waterReminderIntervalSeconds = 60 * 60   // 1 hour cadence
    /// Hour/minute the daily water schedule anchors to (07:10 by default).
    static let waterAnchorHour = 7
    static let waterAnchorMinute = 10
    private static let nextWaterReminderKey = "Nudge.nextWaterReminderAt"
    private static let waterRemindersFiredDayKey = "Nudge.waterRemindersFiredDay" // yyyy-MM-dd
    private static let waterRemindersFiredCountKey = "Nudge.waterRemindersFiredCount"

    /// Tracks which block index we've already fired the "2 min left" warning
    /// for, so it doesn't repeat every second.
    var endingSoonWarnedIndex: Int? = nil

    // Remove-from-screen state
    private var isHiddenFromScreen: Bool = false

    // Constants
    let panelWidth: CGFloat = 196
    let edgeMargin: CGFloat = 20
    let cornerRadius: CGFloat = 12

    // MARK: - App lifecycle

    /// Build a minimal app menu so standard shortcuts (Cmd+Q, Cmd+H, Cmd+W) work.
    func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Nudge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Nudge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    /// Clicking the dock icon when the window is hidden brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            panel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: if another Nudge is already running, exit.
        let me = ProcessInfo.processInfo.processIdentifier
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.nudge.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: myBundleID)
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            NSLog("Nudge: another instance already running, exiting.")
            exit(0)
        }

        // Standalone app — dock icon always present.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()

        loadUserSettings()

        // If onboarding hasn't been completed, show the onboarding panel first.
        if !hasCompletedOnboarding {
            showOnboarding()
            return
        }

        finishLaunching()
    }

    /// Called after onboarding completes (or immediately if already onboarded).
    /// Sets up the main HUD, timers, observers, etc.
    func finishLaunching() {
        loadDoneState()
        loadTodos()
        loadBlockNotes()
        loadWeeklyReflections()
        loadBacklog()
        if waterRemindersEnabled { loadWaterReminderState() }
        buildPanel()
        layoutSubviews()
        wireUpInteractions()

        // Initial schedule + position
        recomputeCurrentBlock(force: true)
        snapToCorner(Corner.saved, animated: false)
        panel.orderFrontRegardless()

        // Per-second tick (clock, countdown, progress, urgency)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(tickTimer!, forMode: .common)

        // Per-minute date-change check
        dayCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDayRollover() }
        }
        RunLoop.main.add(dayCheckTimer!, forMode: .common)

        // Notifications: follow active app & screen changes
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self,
                       selector: #selector(activeAppChanged(_:)),
                       name: NSWorkspace.didActivateApplicationNotification,
                       object: nil)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)

        // Screen sleep / wake — proxy for laptop lid closed / opened
        ws.addObserver(self,
                       selector: #selector(screensDidSleep(_:)),
                       name: NSWorkspace.screensDidSleepNotification,
                       object: nil)
        ws.addObserver(self,
                       selector: #selector(screensDidWake(_:)),
                       name: NSWorkspace.screensDidWakeNotification,
                       object: nil)

        // Sparkle auto-updater — checks for updates automatically.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // One-time cleanup: if a previous version installed a launchd agent,
        // unload and remove it so Nudge is no longer managed by launchd.
        uninstallLaunchdAgentIfPresent()

        // Notifications — for block-change alerts when Nudge is hidden or
        // you're on a fullscreen app. The first call shows the system prompt.
        requestNotificationPermissionIfNeeded()

        // Global Right-Command + B → bring panel back from hidden state.
        registerGlobalUnhideHotkey()

        tick()
        // Now that labels are populated with real text, refit the panel so the
        // bottom "X of Y blocks done" strip isn't clipped.
        resizeMinimizedPanelToFit()
        // First-launch backlog scan — pick up anything from previous days.
        sweepBacklogForOverdueDays()
    }

    // MARK: - Build window

    private func buildPanel() {
        let initialRect = NSRect(x: 0, y: 0, width: panelWidth, height: 260)
        panel = HUDPanel(contentRect: initialRect)
        panel.minSize = NSSize(width: 0, height: 0)
        panel.contentMinSize = NSSize(width: 0, height: 0)
        if let close = panel.standardWindowButton(.closeButton) {
            close.target = self
            close.action = #selector(hideFromTitlebar(_:))
        }
        if let mini = panel.standardWindowButton(.miniaturizeButton) {
            mini.target = self
            mini.action = #selector(hideFromTitlebar(_:))
        }

        // Visual effect background (frosted dark HUD).
        // Light Mood swaps the material to a softer translucent style while
        // staying dark — keeps the existing white text legible.
        visualEffect = NSVisualEffectView(frame: initialRect)
        visualEffect.material = lightMoodEnabled ? .underWindowBackground : .hudWindow
        visualEffect.appearance = NSAppearance(named: .vibrantDark)
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true

        // Container content view
        contentView = HUDContentView(frame: initialRect)
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = false

        // Subtle white border (animatable for urgency states)
        borderLayer = CALayer()
        borderLayer.frame = contentView.bounds
        borderLayer.cornerRadius = cornerRadius
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        borderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer?.addSublayer(borderLayer)

        // Insert visual effect under content
        contentView.addSubview(visualEffect, positioned: .below, relativeTo: nil)
        visualEffect.autoresizingMask = [.width, .height]

        panel.contentView = contentView
    }

    // MARK: - Layout (minimized panel)

    private func layoutSubviews() {
        if minimizedViewMode == "todos" {
            layoutTodosMinimized()
            return
        }
        layoutScheduleMinimized()
    }

    func layoutScheduleMinimized() {
        // Clock — 11pt muted white, right-aligned
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        clockLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        clockLabel.alignment = .right

        // "NOW" header — 8pt uppercase muted
        nowHeaderLabel.stringValue = "NOW"
        nowHeaderLabel.font = NSFont.systemFont(ofSize: 8, weight: .semibold)
        nowHeaderLabel.textColor = NSColor.white.withAlphaComponent(0.45)

        // Current task — 13pt white semibold
        currentTaskLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        currentTaskLabel.textColor = .white
        currentTaskLabel.lineBreakMode = .byTruncatingTail

        // Countdown — 10pt muted
        countdownLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        countdownLabel.textColor = NSColor.white.withAlphaComponent(0.55)

        // Progress bar — thinner
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        progressBar.layer?.cornerRadius = 1.5
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 3).isActive = true

        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
        progressFill.layer?.cornerRadius = 1.5
        progressBar.addSubview(progressFill)

        // Pill buttons — primary "Mark done", secondary "Previous"
        stylePillPrimary(markDoneButton, title: "Mark done")
        stylePillSecondary(markPrevDoneButton, title: "Mark previous done")

        // Expand button (chevron) — top-left of the title strip
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        expandButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        expandButton.attributedTitle = NSAttributedString(
            string: "⤢",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ])
        expandButton.translatesAutoresizingMaskIntoConstraints = false

        // "NEXT" header
        nextHeaderLabel.stringValue = "NEXT"
        nextHeaderLabel.font = NSFont.systemFont(ofSize: 8, weight: .semibold)
        nextHeaderLabel.textColor = NSColor.white.withAlphaComponent(0.45)

        // Next task — 11pt muted
        nextTaskLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        nextTaskLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        nextTaskLabel.lineBreakMode = .byTruncatingTail

        // Progress dots row
        progressDotsRow.orientation = .horizontal
        progressDotsRow.spacing = 2
        progressDotsRow.alignment = .centerY

        // Summary text
        progressSummary.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        progressSummary.textColor = NSColor.white.withAlphaComponent(0.5)

        // Fixed motivational quote — quietly sits at the bottom of the HUD
        dreamsQuoteLabel.stringValue = "\"The future belongs to those who believe in the beauty of their dreams.\""
        dreamsQuoteLabel.font = NSFont.systemFont(ofSize: 8, weight: .regular)
        dreamsQuoteLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        dreamsQuoteLabel.lineBreakMode = .byWordWrapping
        dreamsQuoteLabel.maximumNumberOfLines = 3
        dreamsQuoteLabel.alignment = .center
        dreamsQuoteLabel.preferredMaxLayoutWidth = panelWidth - 28

        // Drag handle (top strip — covers the clock area, also draggable)
        dragHandle = DragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        // Dividers
        let divider1 = makeDivider()
        let divider2 = makeDivider()
        let divider3 = makeDivider()

        // "now" stack (header + task + countdown + progress + pill buttons)
        let buttonsStack = NSStackView(views: [markDoneButton, markPrevDoneButton])
        buttonsStack.orientation = .vertical
        buttonsStack.alignment = .leading
        buttonsStack.spacing = 4

        let nowStack = NSStackView(views: [nowHeaderLabel, currentTaskLabel, countdownLabel, progressBar, buttonsStack])
        nowStack.orientation = .vertical
        nowStack.alignment = .leading
        nowStack.spacing = 3
        nowStack.setCustomSpacing(6, after: progressBar)
        nowStack.setHuggingPriority(.required, for: .vertical)

        // "next" stack
        let nextStack = NSStackView(views: [nextHeaderLabel, nextTaskLabel])
        nextStack.orientation = .vertical
        nextStack.alignment = .leading
        nextStack.spacing = 1

        // Bottom progress strip
        let bottomStack = NSStackView(views: [progressSummary, progressDotsRow])
        bottomStack.orientation = .vertical
        bottomStack.alignment = .leading
        bottomStack.spacing = 3

        // Master vertical stack
        let mainStack = NSStackView(views: [
            clockLabel,
            divider1,
            nowStack,
            divider2,
            nextStack,
            bottomStack,
            divider3,
            dreamsQuoteLabel
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // Wrap mainStack in a root container so we can swap minimized/expanded
        let minRoot = NSView()
        minRoot.translatesAutoresizingMaskIntoConstraints = false
        minRoot.addSubview(mainStack)
        minRoot.addSubview(dragHandle)
        minRoot.addSubview(expandButton)

        contentView.addSubview(minRoot)
        minimizedContentRoot = minRoot

        NSLayoutConstraint.activate([
            minRoot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            minRoot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            minRoot.topAnchor.constraint(equalTo: contentView.topAnchor),
            minRoot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            mainStack.leadingAnchor.constraint(equalTo: minRoot.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: minRoot.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor),

            // Drag handle covers the top strip (clock area) for moving
            dragHandle.topAnchor.constraint(equalTo: minRoot.topAnchor),
            dragHandle.leadingAnchor.constraint(equalTo: minRoot.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor),

            // Expand button — bottom-right of the panel (traffic lights occupy top-left)
            expandButton.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor, constant: -8),
            expandButton.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor, constant: -6),
            expandButton.widthAnchor.constraint(equalToConstant: 16),
            expandButton.heightAnchor.constraint(equalToConstant: 16),

            clockLabel.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 11),
            clockLabel.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -11),

            currentTaskLabel.trailingAnchor.constraint(lessThanOrEqualTo: mainStack.trailingAnchor, constant: -11),
            nextTaskLabel.trailingAnchor.constraint(lessThanOrEqualTo: mainStack.trailingAnchor, constant: -11),

            // Nudge the bottom summary text right so the leading "0" doesn't
            // get clipped by the rounded-corner mask. (Dots row stays put —
            // OK with the first dot being cut off.)
            progressSummary.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 14),

            progressBar.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            divider1.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            divider2.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            divider3.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            dreamsQuoteLabel.widthAnchor.constraint(equalToConstant: panelWidth - 28),
        ])

        // Wire hit-test references
        contentView.dragHandle = dragHandle
        contentView.interactiveViews = [expandButton, markDoneButton, markPrevDoneButton]
        minimizedMainStack = mainStack

        // Initial size — will be refined by resizeMinimizedPanelToFit() after
        // the first tick() populates real label text.
        resizeMinimizedPanelToFit()
    }

    /// Recalculate the minimized panel's height from the mainStack's current
    /// fit and re-snap to the saved corner so nothing gets clipped.
    /// Only valid when the panel is currently in minimized mode — the
    /// `contentView` must not be stretched by expanded-mode constraints.
    func resizeMinimizedPanelToFit() {
        guard !isExpanded, !isInEyeBreak, !isInWaterBreak, let stack = minimizedMainStack else { return }
        contentView.layoutSubtreeIfNeeded()
        let newHeight = ceil(stack.fittingSize.height)
        cachedMinimizedHeight = newHeight
        if abs(panel.frame.height - newHeight) < 0.5 { return }
        let origin = panel.frame.origin
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: panelWidth, height: newHeight),
                       display: false)
        snapToCorner(Corner.saved, animated: false)
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    // MARK: - Todos minimized layout

    func layoutTodosMinimized() {
        // Clock — same style as schedule mode
        clockLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        clockLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        clockLabel.alignment = .right

        // Greeting
        todosMiniGreeting.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        todosMiniGreeting.textColor = .white
        todosMiniGreeting.lineBreakMode = .byTruncatingTail

        // Expand button
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        expandButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        expandButton.attributedTitle = NSAttributedString(
            string: "⤢",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ])
        expandButton.translatesAutoresizingMaskIntoConstraints = false

        // Progress summary for todos
        progressSummary.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        progressSummary.textColor = NSColor.white.withAlphaComponent(0.5)

        // Quick Add To-Do button
        quickAddBtn.title = "+ Quick Add To-Do"
        quickAddBtn.bezelStyle = .inline
        quickAddBtn.isBordered = false
        quickAddBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        quickAddBtn.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        quickAddBtn.target = self
        quickAddBtn.action = #selector(quickAddButtonTapped(_:))

        // Motivational quote
        dreamsQuoteLabel.stringValue = "\"The future belongs to those who believe in the beauty of their dreams.\""
        dreamsQuoteLabel.font = NSFont.systemFont(ofSize: 8, weight: .regular)
        dreamsQuoteLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        dreamsQuoteLabel.lineBreakMode = .byWordWrapping
        dreamsQuoteLabel.maximumNumberOfLines = 3
        dreamsQuoteLabel.alignment = .center
        dreamsQuoteLabel.preferredMaxLayoutWidth = panelWidth - 28

        // Drag handle
        dragHandle = DragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false

        let divider1 = makeDivider()
        let divider2 = makeDivider()

        // Todos list container — will be populated by updateTodosMiniList()
        let todosContainer = NSStackView()
        todosContainer.orientation = .vertical
        todosContainer.alignment = .leading
        todosContainer.spacing = 4
        todosMiniContainer = todosContainer

        let mainStack = NSStackView(views: [
            clockLabel,
            divider1,
            todosMiniGreeting,
            todosContainer,
            quickAddBtn,
            progressSummary,
            divider2,
            dreamsQuoteLabel
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 9, left: 11, bottom: 9, right: 11)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let minRoot = NSView()
        minRoot.translatesAutoresizingMaskIntoConstraints = false
        minRoot.addSubview(mainStack)
        minRoot.addSubview(dragHandle)
        minRoot.addSubview(expandButton)

        contentView.addSubview(minRoot)
        minimizedContentRoot = minRoot

        NSLayoutConstraint.activate([
            minRoot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            minRoot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            minRoot.topAnchor.constraint(equalTo: contentView.topAnchor),
            minRoot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            mainStack.leadingAnchor.constraint(equalTo: minRoot.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: minRoot.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor),

            dragHandle.topAnchor.constraint(equalTo: minRoot.topAnchor),
            dragHandle.leadingAnchor.constraint(equalTo: minRoot.leadingAnchor),
            dragHandle.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor),
            dragHandle.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor),

            expandButton.trailingAnchor.constraint(equalTo: minRoot.trailingAnchor, constant: -8),
            expandButton.bottomAnchor.constraint(equalTo: minRoot.bottomAnchor, constant: -6),
            expandButton.widthAnchor.constraint(equalToConstant: 16),
            expandButton.heightAnchor.constraint(equalToConstant: 16),

            clockLabel.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor, constant: 11),
            clockLabel.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor, constant: -11),

            divider1.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            divider2.widthAnchor.constraint(equalToConstant: panelWidth - 22),
            dreamsQuoteLabel.widthAnchor.constraint(equalToConstant: panelWidth - 28),
        ])

        contentView.dragHandle = dragHandle
        contentView.interactiveViews = [expandButton, quickAddBtn]
        minimizedMainStack = mainStack

        resizeMinimizedPanelToFit()
    }

    /// Refresh the todo rows in the minimized todos view. Called from tick().
    func updateTodosMiniList() {
        guard minimizedViewMode == "todos", let container = todosMiniContainer else { return }

        // Don't rebuild while the user is typing in quick-add
        if isQuickAddActive { return }

        // Clear old rows
        for sub in container.arrangedSubviews { sub.removeFromSuperview() }

        // ── Detail view ──
        if let detailId = miniDetailTodoId,
           let todo = todos.first(where: { $0.id == detailId }) {
            // Hide everything except the container and clock
            if let stack = minimizedMainStack {
                for v in stack.arrangedSubviews where v !== container && v !== clockLabel {
                    v.isHidden = true
                }
            }

            // Back arrow
            let backBtn = NSButton(title: "← Back", target: self, action: #selector(todoMiniBackTapped(_:)))
            backBtn.bezelStyle = .inline
            backBtn.isBordered = false
            backBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            backBtn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
            container.addArrangedSubview(backBtn)

            // Title
            let title = NSTextField(labelWithString: todo.text)
            title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            title.textColor = .white
            title.lineBreakMode = .byWordWrapping
            title.maximumNumberOfLines = 2
            title.preferredMaxLayoutWidth = panelWidth - 28
            container.addArrangedSubview(title)

            // Priority
            let priorityNames = [1: "Urgent", 2: "High", 3: "Medium", 4: "None"]
            let priorityColors: [Int: NSColor] = [1: .systemRed, 2: .systemOrange, 3: .systemBlue, 4: NSColor.white.withAlphaComponent(0.4)]
            let priLabel = NSTextField(labelWithString: "Priority: \(priorityNames[todo.priority] ?? "None")")
            priLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            priLabel.textColor = priorityColors[todo.priority] ?? NSColor.white.withAlphaComponent(0.4)
            container.addArrangedSubview(priLabel)

            // Description
            if !todo.desc.isEmpty {
                let desc = NSTextField(labelWithString: todo.desc)
                desc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                desc.textColor = NSColor.white.withAlphaComponent(0.7)
                desc.lineBreakMode = .byWordWrapping
                desc.maximumNumberOfLines = 5
                desc.preferredMaxLayoutWidth = panelWidth - 28
                container.addArrangedSubview(desc)
            }

            // Due date
            if let due = todo.dueDate {
                let f = DateFormatter()
                f.dateFormat = "d MMM yyyy"
                let dueLabel = NSTextField(labelWithString: "Due: \(f.string(from: due))")
                dueLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
                dueLabel.textColor = NSColor.white.withAlphaComponent(0.5)
                container.addArrangedSubview(dueLabel)
            }

            contentView.interactiveViews = [expandButton, backBtn]
            resizeMinimizedPanelToFit()
            return
        }

        // ── List view (normal) ──
        // Restore hidden views
        if let stack = minimizedMainStack {
            for v in stack.arrangedSubviews { v.isHidden = false }
        }

        // Update greeting
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  todosMiniGreeting.stringValue = "Good morning, \(userName)."
        case 12..<17: todosMiniGreeting.stringValue = "Hey \(userName) — keep going."
        case 17..<21: todosMiniGreeting.stringValue = "Good evening, \(userName)."
        default:      todosMiniGreeting.stringValue = "Late night, \(userName)?"
        }

        let incomplete = todos.prefix(5)
        if incomplete.isEmpty {
            let empty = NSTextField(labelWithString: "No tasks — enjoy the calm ✨")
            empty.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            empty.textColor = NSColor.white.withAlphaComponent(0.45)
            container.addArrangedSubview(empty)
        } else {
            for todo in incomplete {
                let row = makeTodoMiniRow(todo)
                container.addArrangedSubview(row)
            }
        }

        // Update summary
        let total = todos.count
        let doneToday = todosCompletedTodayCount()
        progressSummary.stringValue = "\(doneToday) done today · \(total) remaining"

        // Re-register interactive views
        var interactives: [NSView] = [expandButton, quickAddBtn]
        for sub in container.arrangedSubviews {
            for child in sub.subviews {
                if child is NSButton { interactives.append(child) }
            }
        }
        contentView.interactiveViews = interactives

        resizeMinimizedPanelToFit()
    }

    private func makeTodoMiniRow(_ todo: TodoItem) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5

        // Priority dot
        let dot = NSView()
        dot.wantsLayer = true
        let dotColor: NSColor
        switch todo.priority {
        case 1: dotColor = NSColor.systemRed
        case 2: dotColor = NSColor.systemOrange
        case 3: dotColor = NSColor.systemBlue
        default: dotColor = NSColor.white.withAlphaComponent(0.25)
        }
        dot.layer?.backgroundColor = dotColor.cgColor
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true

        // Checkbox button
        let check = NSButton(title: "○", target: self, action: #selector(todoMiniCheckTapped(_:)))
        check.bezelStyle = .inline
        check.isBordered = false
        check.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        check.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        check.identifier = NSUserInterfaceItemIdentifier(todo.id)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: 16).isActive = true

        // Tap-to-detail button (the text label itself)
        let detailBtn = NSButton(title: todo.text, target: self, action: #selector(todoMiniDetailTapped(_:)))
        detailBtn.bezelStyle = .inline
        detailBtn.isBordered = false
        detailBtn.alignment = .left
        detailBtn.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailBtn.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        detailBtn.lineBreakMode = .byTruncatingTail
        detailBtn.identifier = NSUserInterfaceItemIdentifier(todo.id)

        row.addArrangedSubview(dot)
        row.addArrangedSubview(check)
        row.addArrangedSubview(detailBtn)

        return row
    }

    @objc func todoMiniCheckTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        // If we're viewing this todo's detail, go back to list
        if miniDetailTodoId == id { miniDetailTodoId = nil }
        todos.removeAll { $0.id == id }
        saveTodos()
        incrementTodosCompletedToday()
        updateTodosMiniList()
        // Also refresh expanded view if it's open
        if isExpanded { rebuildExpandedMain() }
    }

    @objc func todoMiniDetailTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        miniDetailTodoId = id
        updateTodosMiniList()
    }

    @objc func todoMiniBackTapped(_ sender: NSButton) {
        miniDetailTodoId = nil
        updateTodosMiniList()
    }

    // MARK: - Traffic-light dot styling

    private func styleTrafficDot(_ btn: NSButton, color: NSColor) {
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.title = ""
        btn.translatesAutoresizingMaskIntoConstraints = false
        // Use an image-based approach: draw a filled circle into the button
        let size: CGFloat = 12
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        btn.image = img
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleNone
        btn.widthAnchor.constraint(equalToConstant: size).isActive = true
        btn.heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    // MARK: - Pill button styling

    func stylePillPrimary(_ btn: PillButton, title: String) {
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
            ])
        btn.invalidateIntrinsicContentSize()
    }

    func stylePillSecondary(_ btn: PillButton, title: String) {
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 10, weight: .medium)
            ])
        btn.invalidateIntrinsicContentSize()
    }

    func stylePillDone(_ btn: PillButton, title: String) {
        // Subtle pill background with a green checkmark prefix.
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: "✓ ", attributes: [
            .foregroundColor: NSColor.systemGreen,
            .font: NSFont.systemFont(ofSize: 11, weight: .heavy)
        ]))
        attr.append(NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold)
        ]))
        btn.attributedTitle = attr
        btn.invalidateIntrinsicContentSize()
    }

    // MARK: - Wire actions

    private func wireUpInteractions() {
        markDoneButton.target = self
        markDoneButton.action = #selector(markDoneTapped(_:))
        markPrevDoneButton.target = self
        markPrevDoneButton.action = #selector(markPrevDoneTapped(_:))
        expandButton.target = self
        expandButton.action = #selector(toggleExpanded(_:))

        dragHandle.onDragEnded = { [weak self] in
            self?.snapToNearestCorner()
        }

        // Global Option-click hold detection (anywhere over the HUD)
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handlePotentialQuitGesture(event: event)
            return event
        }
    }

    // MARK: - Tick

    func tick() {
        // Clock + short date — e.g. "Wed 8 Apr  ·  16:32"
        let dateF = DateFormatter()
        dateF.dateFormat = "EEE d MMM"
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        let now = Date()
        clockLabel.stringValue = "\(dateF.string(from: now))  ·  \(timeF.string(from: now))"

        // In todos mode, refresh the mini todo list; schedule-mode updates below.
        if minimizedViewMode == "todos" && !isExpanded {
            updateTodosMiniList()
        }

        recomputeCurrentBlock()
        updateBlockUI()
        updateUrgencyState()

        // 20-20-20: count real lid-open seconds (not during sleep / active break)
        if eyeBreakEnabled && !screensAsleep && !isInEyeBreak && !isInWaterBreak {
            laptopOpenSeconds += 1
            if laptopOpenSeconds >= Self.eyeBreakIntervalSeconds {
                laptopOpenSeconds = 0
                triggerEyeBreak()
            }
        }

        // Water reminder — wall-clock anchored, NOT lid-open seconds. Fires
        // when we cross the next scheduled time. Re-check every tick so a
        // missed reminder (laptop was closed) pops the moment we're back.
        if waterRemindersEnabled && !isInWaterBreak && !isInEyeBreak && !screensAsleep && now >= nextWaterReminderAt {
            triggerWaterReminder()
        }
        // Live-update the countdown label on the Progress dashboard if visible.
        eyeBreakCountdownLabel?.stringValue = formatEyeBreakRemaining()
        waterCountdownLabel?.stringValue = formatWaterRemaining()

        // Poll for fullscreen state changes every 5 seconds (not every tick).
        // CGWindowListCopyWindowInfo is expensive — calling it every second
        // causes visible lag.
        fullscreenCheckCounter += 1
        if fullscreenCheckCounter >= 5 {
            fullscreenCheckCounter = 0
            let nowFullscreen = isActiveAppFullscreen()
            if nowFullscreen != isAmbientMode {
                isAmbientMode = nowFullscreen
                applyAmbientModeChange()
            }
        }
        if isAmbientMode { updateAmbientPillLabel() }

        // End-of-block warning — fire once when ~2 min remain.
        checkEndOfBlockWarning()

        // Sunday-evening reflection — checked once per minute is plenty.
        if shouldPromptForWeeklyReflection() {
            // Mark dismissed first so we never re-fire even if the user
            // ignores the alert. They can still set it manually later.
            dismissReflectionPromptForThisWeek()
            showWeeklyReflectionPrompt()
        }
    }

    /// Pulse the border + post a notification when the current completable
    /// block is about to end. Fires once per block.
    func checkEndOfBlockWarning() {
        guard let idx = currentBlockIndex else { return }
        let block = todayBlocks[idx]
        guard isCompletable(block) else { return }
        let remaining = block.end.timeIntervalSince(Date())
        // Trigger only when between 90 and 120 seconds remain so a single
        // tick lands inside the window.
        if remaining > 90 && remaining <= 120 && endingSoonWarnedIndex != idx {
            endingSoonWarnedIndex = idx
            postEndingSoonNotification(for: block)
            pulseEndingSoonBorder()
            playGentleChime()
        }
    }

    private func postEndingSoonNotification(for block: ScheduleBlock) {
        let content = UNMutableNotificationContent()
        content.title = "⏳ 2 minutes left"
        content.body = "\(formatBlock(block)) is wrapping up. Bring it home, \(userName)."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "ending-soon-\(Date().timeIntervalSince1970)",
                                        content: content,
                                        trigger: nil)
        notificationCenter?.add(req)
    }

    /// Briefly pulse the HUD border in cyan to draw the eye.
    private func pulseEndingSoonBorder() {
        let original = borderLayer.borderColor
        let originalWidth = borderLayer.borderWidth
        borderLayer.removeAllAnimations()
        borderLayer.borderColor = NSColor.systemTeal.cgColor
        borderLayer.borderWidth = 2
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.4
        anim.duration = 0.6
        anim.autoreverses = true
        anim.repeatCount = 4
        borderLayer.add(anim, forKey: "endingSoon")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            self.borderLayer.removeAnimation(forKey: "endingSoon")
            self.borderLayer.opacity = 1.0
            self.borderLayer.borderColor = original
            self.borderLayer.borderWidth = originalWidth
        }
    }

    /// "12 min" / "59 sec" — how long until the next forced eye break.
    func formatEyeBreakRemaining() -> String {
        let remaining = max(0, Self.eyeBreakIntervalSeconds - laptopOpenSeconds)
        let mins = remaining / 60
        let secs = remaining % 60
        if mins == 0 { return "\(secs) sec" }
        if secs == 0 { return "\(mins) min" }
        return "\(mins) min \(secs) sec"
    }

    /// "23 min" — how long until the next scheduled water reminder fires.
    /// If the next reminder is already overdue (laptop was closed past it),
    /// returns "now".
    func formatWaterRemaining() -> String {
        let remaining = Int(nextWaterReminderAt.timeIntervalSinceNow.rounded())
        if remaining <= 0 { return "now" }
        let mins = remaining / 60
        let secs = remaining % 60
        if mins == 0 { return "\(secs) sec" }
        if secs == 0 { return "\(mins) min" }
        return "\(mins) min \(secs) sec"
    }

    /// Show a full-panel popup telling the user to drink water, mirroring the
    /// 20-20-20 eye break. Every 2nd reminder (~every 2 hours) becomes a
    /// "drink the other half + refill" prompt instead of just "drink half".
    /// NOTE: this does NOT advance `nextWaterReminderAt` — that only moves
    /// when the user hits Done (or Snooze, by a smaller amount). The popup
    /// will keep coming back the next tick if dismissed any other way.
    func triggerWaterReminder() {
        guard !isInWaterBreak else { return }
        // If an eye break is already on screen, the tick loop will retry
        // automatically once the eye break is dismissed (nextWaterReminderAt
        // is in the past, so the next tick that satisfies all the gates will
        // call us again). No asyncAfter needed.
        if isInEyeBreak { return }

        isInWaterBreak = true
        // NOTE: don't reset waterBreakSnoozesUsed here — snooze count carries
        // over across re-fires of the same pending reminder. Done resets it.
        playGentleChime()

        // Backup system notification if the HUD is hidden from the screen.
        if isHiddenFromScreen {
            unhideFromScreen()
            postWaterReminderNotification()
        }

        // Collapse an expanded panel so the overlay owns the compact slot.
        if isExpanded {
            collapsePanel()
        }

        // Hide every other sibling inside contentView — minimized layout,
        // expanded layout, ambient pill — so nothing bleeds through.
        minimizedContentRoot?.isHidden = true
        expandedContentRoot?.isHidden = true
        ambientPillRoot?.isHidden = true

        // Build (or reuse) the water-break overlay.
        if waterBreakRoot == nil {
            buildWaterBreakRoot()
        }
        refreshWaterBreakLabel()
        // Refresh the snooze button label to reflect the carried-over count.
        waterBreakSnoozeButton?.attributedTitle = NSAttributedString(
            string: waterSnoozeButtonTitle(),
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        waterBreakSnoozeButton?.isHidden = (waterBreakSnoozesUsed >= Self.maxWaterBreakSnoozes)
        waterBreakRoot?.isHidden = false
        // Promote to top z-order — see triggerEyeBreak for rationale.
        if let root = waterBreakRoot {
            contentView.addSubview(root, positioned: .above, relativeTo: nil)
        }
        contentView.isExpanded = true  // full hit-testing — Done button must be clickable

        // Resize the panel to fit the bold message, snapped to the saved corner.
        preBreakFrame = panel.frame
        let target = NSSize(width: 300, height: 140)
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let corner = Corner.saved
        let w = target.width, h = target.height
        let frame: NSRect
        switch corner {
        case .topLeft:     frame = NSRect(x: v.minX + edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .topRight:    frame = NSRect(x: v.maxX - w - edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .bottomLeft:  frame = NSRect(x: v.minX + edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        case .bottomRight: frame = NSRect(x: v.maxX - w - edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func buildWaterBreakRoot() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        // Opaque dark background (see buildEyeBreakRoot for rationale).
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        root.layer?.cornerRadius = cornerRadius
        root.layer?.masksToBounds = true
        contentView.addSubview(root)

        // Big blue bold label — text set per-trigger via refreshWaterBreakLabel.
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 15, weight: .heavy)
        label.textColor = NSColor.systemBlue
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        root.addSubview(label)
        waterBreakLabel = label

        // Snooze button — bottom-left
        let snooze = NSButton(title: "Snooze 5 min", target: self,
                              action: #selector(waterBreakSnoozeTapped(_:)))
        snooze.bezelStyle = .inline
        snooze.isBordered = false
        snooze.wantsLayer = true
        snooze.layer?.cornerRadius = 6
        snooze.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        snooze.attributedTitle = NSAttributedString(
            string: waterSnoozeButtonTitle(),
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        snooze.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(snooze)
        waterBreakSnoozeButton = snooze

        // "Done" button — bottom-right
        let done = NSButton(title: "Done", target: self, action: #selector(waterBreakDoneTapped(_:)))
        done.bezelStyle = .inline
        done.isBordered = false
        done.wantsLayer = true
        done.layer?.cornerRadius = 6
        done.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        done.attributedTitle = NSAttributedString(
            string: "Done",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        done.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(done)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -10),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),

            snooze.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            snooze.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            snooze.heightAnchor.constraint(equalToConstant: 24),

            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            done.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            done.widthAnchor.constraint(equalToConstant: 60),
            done.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Bounce animation — vertical translation, autoreverse, infinite.
        label.layer?.removeAllAnimations()
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = -5
        bounce.toValue = 5
        bounce.duration = 0.5
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        label.layer?.add(bounce, forKey: "bounce")

        waterBreakRoot = root
    }

    /// Sets the label text based on whether this is a "drink half" or
    /// "drink the other half + refill" reminder. The fired counter increments
    /// AFTER the popup is dismissed, so we look at (fired + 1) — the bottle
    /// the user is about to drink — to decide which message to show.
    private func refreshWaterBreakLabel() {
        let upcoming = waterRemindersFired + 1
        let isRefillTime = (upcoming % 2 == 0)
        waterBreakLabel?.stringValue = isRefillTime
            ? "Drink the other half\nof your bottle — then refill."
            : "Drink half of your\nbottle of water."
    }

    private func waterSnoozeButtonTitle() -> String {
        let remaining = Self.maxWaterBreakSnoozes - waterBreakSnoozesUsed
        return "Snooze 5 min (\(remaining) left)"
    }

    @objc private func waterBreakDoneTapped(_ sender: NSButton) {
        // Done = user drank. Re-anchor the entire schedule to "now + 1 hour",
        // bump the reminders-fired counter (drives the half/refill toggle),
        // and reset the snooze allowance for the next pending reminder.
        bumpWaterRemindersFiredForToday()
        waterBreakSnoozesUsed = 0
        waterBreakSnoozeButton?.isHidden = false
        nextWaterReminderAt = Date().addingTimeInterval(Double(Self.waterReminderIntervalSeconds))
        saveWaterReminderState()
        endWaterBreak()
    }

    @objc private func waterBreakSnoozeTapped(_ sender: NSButton) {
        guard isInWaterBreak else { return }
        guard waterBreakSnoozesUsed < Self.maxWaterBreakSnoozes else { return }
        waterBreakSnoozesUsed += 1

        // Snooze = defer the SAME pending reminder for a few minutes. Don't
        // touch waterRemindersFired (the user hasn't actually drunk yet) and
        // don't advance the hourly cadence — only push the next-fire time
        // out by the snooze window. The tick loop will pop the popup again.
        nextWaterReminderAt = Date().addingTimeInterval(Double(Self.waterBreakSnoozeSeconds))
        saveWaterReminderState()
        endWaterBreak()
    }

    private func endWaterBreak() {
        guard isInWaterBreak else { return }
        isInWaterBreak = false

        waterBreakRoot?.isHidden = true
        if isAmbientMode {
            ambientPillRoot?.isHidden = false
        } else {
            minimizedContentRoot?.isHidden = false
        }
        contentView.isExpanded = false  // back to click-through minimized mode

        // Always return to the canonical minimized size — matches collapsePanel.
        let height = cachedMinimizedHeight > 0 ? cachedMinimizedHeight : 240
        let size = NSSize(width: panelWidth, height: height)
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let w = size.width, h = size.height
        let target: NSRect
        switch Corner.saved {
        case .topLeft:     target = NSRect(x: v.minX + edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .topRight:    target = NSRect(x: v.maxX - w - edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .bottomLeft:  target = NSRect(x: v.minX + edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        case .bottomRight: target = NSRect(x: v.maxX - w - edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Water reminder persistence

    /// Loads `nextWaterReminderAt` and `waterRemindersFired` from UserDefaults,
    /// or seeds them with sensible defaults on first launch / new day.
    func loadWaterReminderState() {
        let defaults = UserDefaults.standard

        // Today's "fired count" — only valid if it was saved today, else reset.
        let todayKey = self.todayKey(Date())
        let savedDay = defaults.string(forKey: Self.waterRemindersFiredDayKey)
        if savedDay == todayKey {
            waterRemindersFired = defaults.integer(forKey: Self.waterRemindersFiredCountKey)
        } else {
            waterRemindersFired = 0
        }

        // Next-fire time — load if present, else seed to today's anchor.
        if let saved = defaults.object(forKey: Self.nextWaterReminderKey) as? Date {
            nextWaterReminderAt = saved
        } else {
            nextWaterReminderAt = todaysWaterAnchor()
            saveWaterReminderState()
        }
    }

    func saveWaterReminderState() {
        let defaults = UserDefaults.standard
        defaults.set(nextWaterReminderAt, forKey: Self.nextWaterReminderKey)
        defaults.set(self.todayKey(Date()), forKey: Self.waterRemindersFiredDayKey)
        defaults.set(waterRemindersFired, forKey: Self.waterRemindersFiredCountKey)
    }

    /// Increments the fired-today counter, rolling it over to 0 if the day
    /// has changed since the last increment. Drives the half/refill toggle.
    private func bumpWaterRemindersFiredForToday() {
        let defaults = UserDefaults.standard
        let todayKey = self.todayKey(Date())
        let savedDay = defaults.string(forKey: Self.waterRemindersFiredDayKey)
        if savedDay != todayKey {
            waterRemindersFired = 0
        }
        waterRemindersFired += 1
    }

    /// Returns today's first water-anchor time (07:10 by default).
    private func todaysWaterAnchor() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = Self.waterAnchorHour
        comps.minute = Self.waterAnchorMinute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Backup system notification for the water reminder — fired when the
    /// HUD was hidden from the screen so the prompt isn't easy to miss.
    func postWaterReminderNotification() {
        let isRefillTime = ((waterRemindersFired + 1) % 2 == 0)
        let content = UNMutableNotificationContent()
        content.title = "💧 Drink water, \(userName)"
        content.body = isRefillTime
            ? "Drink the other half of your bottle — then refill."
            : "Drink half of your bottle of water."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "water-\(Date().timeIntervalSince1970)",
                                        content: content,
                                        trigger: nil)
        notificationCenter?.add(req)
    }

    // MARK: - Screen sleep / wake (lid proxy)

    @objc private func screensDidSleep(_ note: Notification) {
        screensAsleep = true
    }

    @objc private func screensDidWake(_ note: Notification) {
        screensAsleep = false
    }

    // MARK: - Schedule logic

    func recomputeCurrentBlock(force: Bool = false) {
        if todayBlocks.isEmpty || force {
            todayBlocks = todaysSchedule()
        }
        let now = Date()
        var current: Int? = nil
        for (i, block) in todayBlocks.enumerated() {
            if block.start <= now && now < block.end {
                current = i
                break
            }
        }
        if force || current != currentBlockIndex {
            let oldIndex = currentBlockIndex
            currentBlockIndex = current
            // Notify on real transitions only — not on the initial force load
            // and not when going from "nothing" to a block at startup.
            if !force, oldIndex != nil, let newIdx = current {
                notifyBlockChanged(to: todayBlocks[newIdx])
            }
            // Different block → current/next task text likely changed length;
            // refit so the bottom summary strip isn't clipped.
            DispatchQueue.main.async { [weak self] in
                self?.resizeMinimizedPanelToFit()
            }
        }
    }

    func updateBlockUI() {
        guard let idx = currentBlockIndex else {
            let now = Date()
            let nextBlock = todayBlocks.first(where: { $0.start > now })
            let hasRealBlocks = todayBlocks.contains { isCompletable($0) }

            if let next = nextBlock {
                // In a gap — there's a block coming up
                currentTaskLabel.stringValue = "Nothing to do right now. Woohoo!"
                let remaining = max(0, next.start.timeIntervalSince(now))
                let mins = Int(ceil(remaining / 60.0))
                countdownLabel.stringValue = "Next up in \(formatRemaining(mins))"
                nextTaskLabel.stringValue = formatBlock(next)
            } else if hasRealBlocks {
                // Past all blocks for today
                currentTaskLabel.stringValue = "You're done for the day!"
                countdownLabel.stringValue = ""
                nextTaskLabel.stringValue = "Enjoy the rest of your evening ✨"
            } else {
                currentTaskLabel.stringValue = "No tasks right now"
                countdownLabel.stringValue = "Set up your schedule to get started."
                nextTaskLabel.stringValue = "Enjoy the calm ✨"
            }
            progressFill.frame = .zero
            let completable = todayBlocks.filter { isCompletable($0) }
            let doneCount = completable.filter { isDone($0) }.count
            updateProgressDots(completed: max(0, todayBlocks.count - 1))
            progressSummary.stringValue = "\(doneCount) of \(completable.count) blocks done"
            markDoneButton.isHidden = true
            markPrevDoneButton.isHidden = true
            return
        }
        updateMarkButtons(currentIndex: idx)

        let block = todayBlocks[idx]
        currentTaskLabel.stringValue = formatBlock(block)

        let now = Date()
        let remaining = max(0, block.end.timeIntervalSince(now))
        let totalMins = Int(ceil(remaining / 60.0))
        // Countdown line: "16:30–17:20  ·  1 hr 13 min left"
        countdownLabel.stringValue = "\(formatTimeRange(block))  ·  \(formatRemaining(totalMins))"

        // Progress fill
        let total = block.end.timeIntervalSince(block.start)
        let elapsed = max(0, min(total, now.timeIntervalSince(block.start)))
        let frac = total > 0 ? CGFloat(elapsed / total) : 0
        let barWidth = panelWidth - 22
        progressFill.frame = NSRect(x: 0, y: 0, width: barWidth * frac, height: 3)

        // Next task — append the duration in brackets, e.g. "Break (10 min)"
        if idx + 1 < todayBlocks.count {
            let next = todayBlocks[idx + 1]
            let nextMins = Int(round(next.end.timeIntervalSince(next.start) / 60.0))
            nextTaskLabel.stringValue = "\(formatBlock(next)) (\(formatDurationShort(nextMins)))"
        } else {
            nextTaskLabel.stringValue = "—"
        }

        // Bottom summary — count completed, denominator = completable blocks
        let completable = todayBlocks.filter { isCompletable($0) }
        let doneCount = completable.filter { isDone($0) }.count
        progressSummary.stringValue = "\(doneCount) of \(completable.count) blocks done"
        updateProgressDots(completed: idx)

        // Refresh expanded view ONLY if the current block index changed.
        if isExpanded && currentBlockIndex != lastRenderedExpandedBlockIndex {
            lastRenderedExpandedBlockIndex = currentBlockIndex
            rebuildExpandedMain()
        }
    }

    private func updateMarkButtons(currentIndex idx: Int) {
        let cur = todayBlocks[idx]

        // Current "mark done" pill — hidden for breaks/sleep
        if isCompletable(cur) {
            markDoneButton.isHidden = false
            if isDone(cur) {
                stylePillDone(markDoneButton, title: "Done")
            } else {
                stylePillPrimary(markDoneButton, title: "Mark done")
            }
        } else {
            markDoneButton.isHidden = true
        }

        // Previous-done pill — hidden if no previous completable block
        if let prevIdx = previousCompletableIndex(before: idx) {
            let prev = todayBlocks[prevIdx]
            let short = truncatedName(prev.name, max: 14)
            markPrevDoneButton.isHidden = false
            if isDone(prev) {
                stylePillDone(markPrevDoneButton, title: "Prev: \(short)")
            } else {
                stylePillSecondary(markPrevDoneButton, title: "Mark prev: \(short)")
            }
        } else {
            markPrevDoneButton.isHidden = true
        }
    }

    /// Truncate a long block name with an ellipsis so the minimized pill
    /// stays visually compact.
    private func truncatedName(_ name: String, max: Int) -> String {
        if name.count <= max { return name }
        return String(name.prefix(max - 1)) + "…"
    }

    func formatBlock(_ block: ScheduleBlock?) -> String {
        guard let block = block else { return "—" }
        if let e = block.emoji { return "\(e) \(block.name)" }
        return block.name
    }

    /// "16:30–17:20" — uses 24-hour format to match the clock label.
    func formatTimeRange(_ block: ScheduleBlock) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: block.start))–\(f.string(from: block.end))"
    }

    /// "1 hr 13 min left" / "12 min left" / "2 hr left"
    func formatRemaining(_ totalMins: Int) -> String {
        let hrs = totalMins / 60
        let mins = totalMins % 60
        if hrs == 0 { return "\(mins) min left" }
        if mins == 0 { return "\(hrs) hr left" }
        return "\(hrs) hr \(mins) min left"
    }

    /// Returns the time-of-day color for a block based on its start time.
    /// Blocks that span across periods take the color of the period they
    /// START in, per the user's request.
    func timeOfDayColor(for block: ScheduleBlock) -> NSColor {
        let h = Calendar.current.component(.hour, from: block.start)
        switch h {
        case 5..<12:  return NSColor.systemYellow      // morning
        case 12..<17: return NSColor.systemOrange      // afternoon
        case 17..<21: return NSColor.systemPurple      // evening
        default:      return NSColor.systemIndigo      // night
        }
    }

    /// Compact duration label for the NEXT block — "10 min", "1 hr", "1 hr 20 min".
    func formatDurationShort(_ totalMins: Int) -> String {
        let hrs = totalMins / 60
        let mins = totalMins % 60
        if hrs == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hrs) hr" }
        return "\(hrs) hr \(mins) min"
    }

    private func updateProgressDots(completed: Int) {
        progressDotsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for i in 0..<todayBlocks.count {
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 1.5
            let alpha: CGFloat
            if i < completed {
                alpha = 0.85
            } else if i == completed {
                alpha = 0.55
            } else {
                alpha = 0.18
            }
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 4).isActive = true
            progressDotsRow.addArrangedSubview(dot)
        }
    }

    // MARK: - Mark done actions

    @objc func markDoneTapped(_ sender: NSButton) {
        guard let idx = currentBlockIndex else { return }
        let block = todayBlocks[idx]
        guard isCompletable(block) else { return }
        setDone(block, !isDone(block))
        tick()
    }

    @objc func markPrevDoneTapped(_ sender: NSButton) {
        guard let idx = currentBlockIndex,
              let prevIdx = previousCompletableIndex(before: idx) else { return }
        let prev = todayBlocks[prevIdx]
        setDone(prev, !isDone(prev))
        tick()
    }

    // MARK: - Remove from screen (hide / unhide)

    func unhideFromScreen() {
        guard isHiddenFromScreen else { return }
        isHiddenFromScreen = false
        panel.orderFrontRegardless()
    }

    // MARK: - Urgency / border pulse

    private func updateUrgencyState() {
        guard let idx = currentBlockIndex else {
            stopBorderPulse(); return
        }
        let block = todayBlocks[idx]
        // No urgency for non-completable blocks (Break/Sleep) or already-done blocks
        if !isCompletable(block) || isDone(block) {
            stopBorderPulse(); return
        }
        let elapsed = Date().timeIntervalSince(block.start)
        if elapsed > 15 * 60 {
            startBorderPulse(.red)
        } else if elapsed > 5 * 60 {
            startBorderPulse(.amber)
        } else {
            stopBorderPulse()
        }
    }

    private func startBorderPulse(_ state: PulseState) {
        guard pulseState != state else { return }
        pulseState = state

        let color: NSColor
        let duration: CFTimeInterval
        switch state {
        case .amber:
            color = NSColor.systemOrange
            duration = 1.6
        case .red:
            color = NSColor.systemRed
            duration = 0.7
        case .none:
            return
        }

        borderLayer.borderWidth = 1.5
        borderLayer.borderColor = color.cgColor

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.4
        anim.toValue = 0.9
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        borderLayer.add(anim, forKey: "pulse")
    }

    private func stopBorderPulse() {
        pulseState = .none
        borderLayer.removeAnimation(forKey: "pulse")
        borderLayer.opacity = 1.0
        borderLayer.borderWidth = 0.5
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    // MARK: - Day rollover

    private func checkDayRollover() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != lastDayCheck {
            lastDayCheck = today
            todayBlocks = todaysSchedule()
            recomputeCurrentBlock(force: true)
            sweepBacklogForOverdueDays()
            tick()
        }
    }

    // MARK: - Active app / screen following

    @objc private func activeAppChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.followActiveAppScreen()
        }
    }

    @objc private func screenParamsChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.followActiveAppScreen()
        }
    }

    private func followActiveAppScreen() {
        // Detect fullscreen state of the active app and toggle ambient mode.
        let nowFullscreen = isActiveAppFullscreen()
        if nowFullscreen != isAmbientMode {
            isAmbientMode = nowFullscreen
            applyAmbientModeChange()
        }
        snapToCorner(Corner.saved, animated: true)
    }

    /// Detect whether the frontmost app is in macOS native fullscreen mode.
    ///
    /// We can't use a fixed dimension comparison because Chrome and Safari
    /// often add a 1–4pt margin around their fullscreen window, and external
    /// monitors have non-integer scale factors that throw off width matches.
    ///
    /// The reliable signal is: in fullscreen, macOS hides the menu bar AND
    /// the dock, so visibleFrame == frame for the screen the active window
    /// is on. We pair that with a "the active app actually has a window
    /// covering most of that screen" check so we don't trigger when the
    /// menu bar is auto-hidden for an unrelated reason.
    private func isActiveAppFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        let pid = frontApp.processIdentifier
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // Find the active app's largest on-screen window.
        var biggestWin: CGRect? = nil
        var biggestArea: CGFloat = 0
        for w in windows {
            guard let wpid = w[kCGWindowOwnerPID as String] as? pid_t, wpid == pid,
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0,
                              y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0,
                              height: bounds["Height"] ?? 0)
            let area = rect.width * rect.height
            if area > biggestArea {
                biggestArea = area
                biggestWin = rect
            }
        }
        guard let win = biggestWin else { return false }

        // CGWindow coords are top-left origin. To find the screen this window
        // sits on, flip the window midpoint into NSScreen coords (bottom-left)
        // and ask each screen if it contains the point.
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        let midX = win.midX
        let midYTopLeft = win.midY
        let midYBottomLeft = mainTop - midYTopLeft
        let midPoint = CGPoint(x: midX, y: midYBottomLeft)

        var hostScreen: NSScreen? = nil
        for screen in NSScreen.screens where screen.frame.contains(midPoint) {
            hostScreen = screen
            break
        }
        guard let screen = hostScreen else { return false }

        // The fullscreen test: covers >= 95% of the screen frame. We're
        // generous with the threshold so Chrome's 1–4pt margins still count.
        let screenArea = screen.frame.width * screen.frame.height
        guard screenArea > 0 else { return false }
        let coverage = (win.width * win.height) / screenArea
        return coverage >= 0.95
    }

    /// Switch the HUD between full minimized layout and a tiny ambient pill.
    func applyAmbientModeChange() {
        // If the panel is expanded and we're entering fullscreen, collapse
        // first so the big panel doesn't block the fullscreen app.
        if isExpanded && isAmbientMode {
            collapsePanel()
        }
        guard !isExpanded else { return }

        if isAmbientMode {
            // Tear down the minimized content entirely. Its layout
            // constraints (panelWidth = 196 dividers, mainStack edge insets,
            // etc.) prevent the contentView from shrinking below 196pt, so
            // hiding alone isn't enough — we have to remove the subviews
            // from the hierarchy. We'll rebuild on exit.
            minimizedContentRoot?.removeFromSuperview()
            minimizedContentRoot = nil

            if ambientPillRoot == nil { buildAmbientPill() }
            ambientPillRoot?.isHidden = false

            // Lock the panel size to a tiny pill.
            let target = NSSize(width: 200, height: 28)
            panel.contentMinSize = target
            panel.contentMaxSize = target
            // Use the FULL screen frame (not visibleFrame) — in fullscreen
            // the menu bar and Dock are hidden so we want true edges.
            let frame = ambientFrameForCorner(Corner.saved, size: target)
            panel.setFrame(frame, display: true)
            updateAmbientPillLabel()
        } else {
            // Tear down the ambient pill so its constraints don't pin the
            // contentView at the pill width.
            ambientPillRoot?.removeFromSuperview()
            ambientPillRoot = nil
            ambientPillLabel = nil
            ambientPillCountdown = nil
            contentView.dragHandle = nil

            // Unlock the panel.
            panel.contentMinSize = NSSize(width: 0, height: 0)
            panel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                          height: CGFloat.greatestFiniteMagnitude)

            // Rebuild the minimized layout from scratch (this also rewires
            // contentView.dragHandle to the new minimized drag strip).
            layoutSubviews()
            tick()
            resizeMinimizedPanelToFit()
        }
    }

    private var ambientPillLabel: NSTextField?
    private var ambientPillCountdown: NSTextField?

    private func buildAmbientPill() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        contentView.addSubview(root)

        // Drag handle covering the entire pill — same drag-to-snap behavior
        // as the main HUD's top strip.
        let drag = DragHandleView()
        drag.translatesAutoresizingMaskIntoConstraints = false
        drag.onDragEnded = { [weak self] in self?.snapToNearestCorner() }
        root.addSubview(drag)

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.95)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        ambientPillLabel = label

        let countdown = NSTextField(labelWithString: "")
        countdown.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countdown.textColor = NSColor.white.withAlphaComponent(0.6)
        countdown.alignment = .right
        countdown.lineBreakMode = .byClipping
        countdown.translatesAutoresizingMaskIntoConstraints = false
        countdown.setContentHuggingPriority(.required, for: .horizontal)
        countdown.setContentCompressionResistancePriority(.required, for: .horizontal)
        root.addSubview(countdown)
        ambientPillCountdown = countdown

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Drag handle fills the whole pill so any click + drag moves it.
            drag.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            drag.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            drag.topAnchor.constraint(equalTo: root.topAnchor),
            drag.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: countdown.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            countdown.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            countdown.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        // Make sure the click-through hit-testing in HUDContentView routes
        // taps over the pill to the drag handle so the user can grab it.
        contentView.dragHandle = drag
        ambientPillRoot = root
    }

    /// Like frameForCorner but anchored on screen.frame (true edges), not
    /// visibleFrame. Used for the ambient pill in fullscreen mode where the
    /// menu bar and Dock are hidden.
    func ambientFrameForCorner(_ corner: Corner, size: NSSize) -> NSRect {
        let screen = screenContainingActiveApp()
        let f = screen.frame
        let w = size.width, h = size.height
        let m: CGFloat = 6  // tiny inset so the pill isn't flush against the edge
        switch corner {
        case .topLeft:     return NSRect(x: f.minX + m, y: f.maxY - h - m, width: w, height: h)
        case .topRight:    return NSRect(x: f.maxX - w - m, y: f.maxY - h - m, width: w, height: h)
        case .bottomLeft:  return NSRect(x: f.minX + m, y: f.minY + m, width: w, height: h)
        case .bottomRight: return NSRect(x: f.maxX - w - m, y: f.minY + m, width: w, height: h)
        }
    }

    func updateAmbientPillLabel() {
        guard isAmbientMode else { return }
        if let idx = currentBlockIndex {
            let block = todayBlocks[idx]
            ambientPillLabel?.stringValue = formatBlock(block)
            let remaining = max(0, block.end.timeIntervalSince(Date()))
            let totalMins = Int(ceil(remaining / 60.0))
            ambientPillCountdown?.stringValue = formatDurationShort(totalMins)
        } else {
            ambientPillLabel?.stringValue = "—"
            ambientPillCountdown?.stringValue = ""
        }
    }

    func screenContainingActiveApp() -> NSScreen {
        // Try to find the active app's frontmost window screen.
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            let pid = frontApp.processIdentifier
            let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            if let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
                for w in windows {
                    if let wpid = w[kCGWindowOwnerPID as String] as? pid_t, wpid == pid,
                       let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] {
                        let rect = CGRect(x: bounds["X"] ?? 0,
                                          y: bounds["Y"] ?? 0,
                                          width: bounds["Width"] ?? 0,
                                          height: bounds["Height"] ?? 0)
                        // CGWindow coords are top-left origin; map to screen by midpoint.
                        let mid = CGPoint(x: rect.midX, y: rect.midY)
                        for screen in NSScreen.screens {
                            let f = screen.frame
                            let mainTop = NSScreen.screens.first?.frame.maxY ?? f.maxY
                            let topLeftFrame = CGRect(x: f.minX,
                                                      y: mainTop - f.maxY,
                                                      width: f.width,
                                                      height: f.height)
                            if topLeftFrame.contains(mid) {
                                return screen
                            }
                        }
                    }
                }
            }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    // MARK: - Corner snapping

    func snapToNearestCorner() {
        if snapToCornerDisabled { return }
        let screen = screenContainingActiveApp()
        // In ambient (fullscreen) mode the menu bar / Dock are hidden so the
        // true edges are screen.frame; otherwise use visibleFrame.
        let bounds = isAmbientMode ? screen.frame : screen.visibleFrame
        let f = panel.frame
        let cx = f.midX, cy = f.midY
        let scx = bounds.midX, scy = bounds.midY

        let corner: Corner
        switch (cx < scx, cy < scy) {
        case (true,  true):  corner = .bottomLeft
        case (false, true):  corner = .bottomRight
        case (true,  false): corner = .topLeft
        case (false, false): corner = .topRight
        }
        Corner.saved = corner
        snapToCorner(corner, animated: true)
    }

    private func snapToCorner(_ corner: Corner, animated: Bool) {
        let screen = screenContainingActiveApp()
        // Same fullscreen-aware bounds choice as snapToNearestCorner.
        let bounds = isAmbientMode ? screen.frame : screen.visibleFrame
        let margin: CGFloat = isAmbientMode ? 6 : edgeMargin
        let w = panel.frame.width
        let h = panel.frame.height

        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = bounds.minX + margin
            y = bounds.maxY - h - margin
        case .topRight:
            x = bounds.maxX - w - margin
            y = bounds.maxY - h - margin
        case .bottomLeft:
            x = bounds.minX + margin
            y = bounds.minY + margin
        case .bottomRight:
            x = bounds.maxX - w - margin
            y = bounds.minY + margin
        }

        let target = NSRect(x: x, y: y, width: w, height: h)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    // MARK: - Quit gesture (Option + 3s hold anywhere on HUD)

    private func handlePotentialQuitGesture(event: NSEvent) {
        guard let win = event.window, win === panel else {
            cancelQuitHold()
            return
        }
        switch event.type {
        case .leftMouseDown:
            if event.modifierFlags.contains(.option) {
                beginQuitHold()
            }
        case .leftMouseUp:
            cancelQuitHold()
        case .flagsChanged:
            if !event.modifierFlags.contains(.option) {
                cancelQuitHold()
            }
        default: break
        }
    }

    private func beginQuitHold() {
        quitHoldStart = Date()
        borderLayer.removeAllAnimations()
        let anim = CABasicAnimation(keyPath: "borderColor")
        anim.fromValue = NSColor.white.withAlphaComponent(0.15).cgColor
        anim.toValue = NSColor.white.withAlphaComponent(1.0).cgColor
        anim.duration = 3.0
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        borderLayer.borderWidth = 1.5
        borderLayer.add(anim, forKey: "quitHold")

        quitHoldTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.completeQuit() }
        }
    }

    private func cancelQuitHold() {
        quitHoldStart = nil
        quitHoldTimer?.invalidate()
        quitHoldTimer = nil
        borderLayer.removeAnimation(forKey: "quitHold")
        let oldState = pulseState
        pulseState = .none
        if oldState != .none {
            startBorderPulse(oldState)
        } else {
            stopBorderPulse()
        }
    }

    private func completeQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - 20-20-20 eye break

    private func triggerEyeBreak() {
        guard !isInEyeBreak else { return }
        // If a water break is already on screen, wait for the user to
        // dismiss/snooze it before stealing the overlay. Retry in 60s.
        if isInWaterBreak {
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
                Task { @MainActor in self?.triggerEyeBreak() }
            }
            return
        }
        isInEyeBreak = true
        eyeBreakSnoozesUsed = 0  // fresh allowance per break
        playGentleChime()

        // If the panel is currently hidden via the Hide-from-screen button,
        // bring it back so the user can actually see the bouncing message,
        // and also fire a system notification as a backup channel.
        if isHiddenFromScreen {
            unhideFromScreen()
            postEyeBreakNotification()
        }

        // If expanded, collapse first so the overlay takes the compact slot.
        if isExpanded {
            collapsePanel()
        }

        // Hide every other sibling inside contentView — minimized layout,
        // expanded layout, ambient pill — so nothing can bleed through
        // behind the overlay.
        minimizedContentRoot?.isHidden = true
        expandedContentRoot?.isHidden = true
        ambientPillRoot?.isHidden = true

        // Build (or reuse) the eye-break overlay.
        if eyeBreakRoot == nil {
            buildEyeBreakRoot()
        }
        eyeBreakRoot?.isHidden = false
        // Promote to the top of contentView's subview z-order. Re-adding an
        // existing subview with `.above` simply reorders it — this guarantees
        // the overlay sits above any siblings added after it was first built.
        if let root = eyeBreakRoot {
            contentView.addSubview(root, positioned: .above, relativeTo: nil)
        }
        contentView.isExpanded = true  // full hit-testing — Done button must be clickable

        // Resize the panel to fit the bold message, snapped to the saved corner.
        preBreakFrame = panel.frame
        let target = NSSize(width: 300, height: 140)
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let corner = Corner.saved
        let w = target.width, h = target.height
        let frame: NSRect
        switch corner {
        case .topLeft:     frame = NSRect(x: v.minX + edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .topRight:    frame = NSRect(x: v.maxX - w - edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .bottomLeft:  frame = NSRect(x: v.minX + edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        case .bottomRight: frame = NSRect(x: v.maxX - w - edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func buildEyeBreakRoot() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        // Opaque dark background — prevents the minimized content (or any
        // other sibling in contentView) from bleeding through if z-order or
        // isHidden state gets out of sync. The panel's visualEffect blur
        // sits below this, so we stay visually consistent with the HUD.
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor
        root.layer?.cornerRadius = cornerRadius
        root.layer?.masksToBounds = true
        contentView.addSubview(root)

        // Big red bold label
        let label = NSTextField(labelWithString: "Look out of the window\nfor 20 seconds.")
        label.font = NSFont.systemFont(ofSize: 16, weight: .heavy)
        label.textColor = NSColor.systemRed
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.wantsLayer = true
        root.addSubview(label)

        // Snooze button — bottom-left
        let snooze = NSButton(title: "Snooze 2 min", target: self,
                              action: #selector(eyeBreakSnoozeTapped(_:)))
        snooze.bezelStyle = .inline
        snooze.isBordered = false
        snooze.wantsLayer = true
        snooze.layer?.cornerRadius = 6
        snooze.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        snooze.attributedTitle = NSAttributedString(
            string: snoozeButtonTitle(),
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        snooze.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(snooze)
        eyeBreakSnoozeButton = snooze

        // "Done" button — bottom-right
        let done = NSButton(title: "Done", target: self, action: #selector(eyeBreakDoneTapped(_:)))
        done.bezelStyle = .inline
        done.isBordered = false
        done.wantsLayer = true
        done.layer?.cornerRadius = 6
        done.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        done.attributedTitle = NSAttributedString(
            string: "Done",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        done.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(done)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -10),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),

            snooze.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            snooze.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            snooze.heightAnchor.constraint(equalToConstant: 24),

            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            done.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            done.widthAnchor.constraint(equalToConstant: 60),
            done.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Bounce animation — vertical translation, autoreverse, infinite.
        label.layer?.removeAllAnimations()
        let bounce = CABasicAnimation(keyPath: "transform.translation.y")
        bounce.fromValue = -5
        bounce.toValue = 5
        bounce.duration = 0.5
        bounce.autoreverses = true
        bounce.repeatCount = .infinity
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        label.layer?.add(bounce, forKey: "bounce")

        eyeBreakRoot = root
    }

    private func snoozeButtonTitle() -> String {
        let remaining = Self.maxEyeBreakSnoozes - eyeBreakSnoozesUsed
        return "Snooze 2 min (\(remaining) left)"
    }

    @objc private func eyeBreakDoneTapped(_ sender: NSButton) {
        endEyeBreak()
    }

    @objc private func eyeBreakSnoozeTapped(_ sender: NSButton) {
        guard isInEyeBreak else { return }
        guard eyeBreakSnoozesUsed < Self.maxEyeBreakSnoozes else { return }
        eyeBreakSnoozesUsed += 1

        // Tear down the overlay so the user can keep working.
        endEyeBreak()
        // Re-trigger the break after the snooze window. Don't increment
        // laptopOpenSeconds — we already crossed the 20-min threshold.
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(Self.eyeBreakSnoozeSeconds)) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                // Hold onto the snooze count across the re-trigger by
                // using a marker variable: triggerEyeBreak resets it,
                // so we restore it after.
                let used = self.eyeBreakSnoozesUsed
                self.triggerEyeBreak()
                self.eyeBreakSnoozesUsed = used
                self.eyeBreakSnoozeButton?.attributedTitle = NSAttributedString(
                    string: self.snoozeButtonTitle(),
                    attributes: [
                        .foregroundColor: NSColor.white,
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
                    ])
                if used >= Self.maxEyeBreakSnoozes {
                    self.eyeBreakSnoozeButton?.isHidden = true
                }
            }
        }
    }

    private func endEyeBreak() {
        guard isInEyeBreak else { return }
        isInEyeBreak = false

        eyeBreakRoot?.isHidden = true
        // In ambient mode the minimized root is nil and the pill owns the UI.
        if isAmbientMode {
            ambientPillRoot?.isHidden = false
        } else {
            minimizedContentRoot?.isHidden = false
        }
        contentView.isExpanded = false  // back to click-through minimized mode

        // Always return to the canonical minimized size — matches collapsePanel.
        let height = cachedMinimizedHeight > 0 ? cachedMinimizedHeight : 240
        let size = NSSize(width: panelWidth, height: height)
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let w = size.width, h = size.height
        let target: NSRect
        switch Corner.saved {
        case .topLeft:     target = NSRect(x: v.minX + edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .topRight:    target = NSRect(x: v.maxX - w - edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .bottomLeft:  target = NSRect(x: v.minX + edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        case .bottomRight: target = NSRect(x: v.maxX - w - edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Legacy launchd cleanup
    //
    // Earlier versions of Nudge installed a launchd agent at
    // ~/Library/LaunchAgents/com.nudge.launcher.plist so the app would
    // auto-restart. That behavior has been removed — this function tears
    // down any leftover agent from prior installs.

    private var launchAgentURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib.appendingPathComponent("LaunchAgents/com.nudge.launcher.plist")
    }

    private func uninstallLaunchdAgentIfPresent() {
        let dest = launchAgentURL
        guard FileManager.default.fileExists(atPath: dest.path) else { return }

        let unload = Process()
        unload.launchPath = "/bin/launchctl"
        unload.arguments = ["unload", dest.path]
        try? unload.run()
        unload.waitUntilExit()

        try? FileManager.default.removeItem(at: dest)
    }

    // MARK: - Permissions

    private func requestNotificationPermissionIfNeeded() {
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Lazily cached notification center — created once so repeated
    /// `.current()` calls don't hit the assertion that ad-hoc signed
    /// apps sometimes trip.
    private lazy var notificationCenter: UNUserNotificationCenter? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }()

    /// System notification for the eye-break — used as a backup when the
    /// panel was hidden so the message isn't easy to miss.
    func postEyeBreakNotification() {
        let content = UNMutableNotificationContent()
        content.title = "👀 20-20-20 break"
        content.body = "Look out the window for 20 seconds, \(userName)."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "eye-break-\(Date().timeIntervalSince1970)",
                                        content: content,
                                        trigger: nil)
        notificationCenter?.add(req)
    }

    /// Fire a system notification when the current block changes. Skipped on
    /// initial load and for non-completable blocks (Break / Sleep).
    func notifyBlockChanged(to block: ScheduleBlock) {
        guard isCompletable(block) else { return }
        let totalMins = max(1, Int(round(block.end.timeIntervalSince(block.start) / 60.0)))
        let content = UNMutableNotificationContent()
        content.title = formatBlock(block)
        content.body = "Now · \(formatTimeRange(block)) · \(formatDurationShort(totalMins))"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content,
                                        trigger: nil)
        notificationCenter?.add(req)
        playGentleChime()
    }

    /// A soft system chime — used for block transitions and the eye-break.
    /// Tries the gentle "Tink" first; falls back to .default if not present.
    func playGentleChime() {
        if let s = NSSound(named: NSSound.Name("Tink")) {
            s.play()
        } else {
            NSSound.beep()
        }
    }

    /// Apply the light-mood material to the live visual effect view without
    /// rebuilding the panel. Used by the More tab toggle.
    /// Light Mood stays dark-themed but uses a softer material so the HUD
    /// feels less intense (the original "light = white" approach broke text
    /// legibility everywhere).
    func applyLightMoodTheme() {
        visualEffect.material = lightMoodEnabled ? .underWindowBackground : .hudWindow
        visualEffect.appearance = NSAppearance(named: .vibrantDark)
    }

    /// Returns a text color appropriate for the current theme. Always white
    /// since both modes are dark-themed; the Light Mood material is just a
    /// softer frosted backdrop. Kept as a function so future themes can plug
    /// in without touching every callsite.
    func themedTextColor(alpha: CGFloat = 1.0) -> NSColor {
        return NSColor.white.withAlphaComponent(alpha)
    }

    // MARK: - Global hotkey: Right Command + B

    private func registerGlobalUnhideHotkey() {
        // Silently check accessibility trust — do not prompt on every launch.
        // The onboarding flow and Settings page handle prompting the user.
        let _ = AXIsProcessTrusted()

        // Global monitor — fires while Nudge is in the background.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isRightCommandB(event) {
                Task { @MainActor in self?.unhideFromScreen() }
            } else if Self.isRightCommandD(event) {
                Task { @MainActor in self?.markCurrentBlockDoneViaHotkey() }
            // } else if Self.isControlOptionN(event) {
            //     Task { @MainActor in self?.triggerQuickAdd() }
            }
        }
        // Local monitor — covers the rare case Nudge itself has focus.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if Self.isRightCommandB(event) {
                Task { @MainActor in self?.unhideFromScreen() }
                return nil
            }
            if Self.isRightCommandD(event) {
                Task { @MainActor in self?.markCurrentBlockDoneViaHotkey() }
                return nil
            }
            // if Self.isControlOptionN(event) {
            //     Task { @MainActor in self?.triggerQuickAdd() }
            //     return nil
            // }
            // Escape dismisses quick-add
            if event.keyCode == 53, self?.isQuickAddActive == true {
                Task { @MainActor in self?.dismissQuickAdd() }
                return nil
            }
            return event
        }
    }

    /// Right-command bit in the device-specific portion of NSEvent.modifierFlags.
    /// (NX_DEVICERCMDKEYMASK = 0x10) — distinguishes from left command (0x08).
    private static func isRightCommandB(_ event: NSEvent) -> Bool {
        let rightCmdMask: UInt = 0x10
        let bKeyCode: UInt16 = 11
        return (event.modifierFlags.rawValue & rightCmdMask) != 0
            && event.keyCode == bKeyCode
    }

    private static func isRightCommandD(_ event: NSEvent) -> Bool {
        let rightCmdMask: UInt = 0x10
        let dKeyCode: UInt16 = 2
        return (event.modifierFlags.rawValue & rightCmdMask) != 0
            && event.keyCode == dKeyCode
    }

    // MARK: - Quick-add (⌃⌥N global hotkey — commented out, kept for future use)
    /*
    private static func isControlOptionN(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let nKeyCode: UInt16 = 45
        return flags.contains(.control) && flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.shift)
            && event.keyCode == nKeyCode
    }

    func triggerQuickAdd() {
        if isHiddenFromScreen { unhideFromScreen() }
        if isExpanded { collapsePanel() }
        panel.orderFrontRegardless()
        isQuickAddActive = true
        showQuickAddField()
    }
    */

    /// Show inline quick-add field in the todos minimized view.
    @objc func quickAddButtonTapped(_ sender: Any?) {
        guard minimizedViewMode == "todos" else { return }
        isQuickAddActive = true

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()

        if let stack = minimizedMainStack {
            for v in stack.arrangedSubviews where v !== clockLabel {
                v.isHidden = true
            }
        }
        if let tc = todosMiniContainer {
            tc.isHidden = false
            for sub in tc.arrangedSubviews { sub.removeFromSuperview() }

            let prompt = NSTextField(labelWithString: "Quick add a reminder:")
            prompt.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            prompt.textColor = NSColor.white.withAlphaComponent(0.6)
            tc.addArrangedSubview(prompt)

            let field = NSTextField()
            field.placeholderString = "Type and press Enter..."
            field.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            field.textColor = .white
            field.backgroundColor = NSColor.white.withAlphaComponent(0.1)
            field.isBordered = false
            field.isBezeled = false
            field.focusRingType = .none
            field.wantsLayer = true
            field.layer?.cornerRadius = 5
            field.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: panelWidth - 30).isActive = true
            field.heightAnchor.constraint(equalToConstant: 24).isActive = true
            field.target = self
            field.action = #selector(quickAddFieldSubmitted(_:))
            quickAddField = field
            tc.addArrangedSubview(field)

            let hint = NSTextField(labelWithString: "Press Esc to cancel")
            hint.font = NSFont.systemFont(ofSize: 8, weight: .regular)
            hint.textColor = NSColor.white.withAlphaComponent(0.3)
            tc.addArrangedSubview(hint)
        }

        resizeMinimizedPanelToFit()

        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        if let field = quickAddField {
            panel.makeFirstResponder(field)
        }
    }

    @objc func quickAddFieldSubmitted(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let todo = TodoItem(text: text)
            todos.insert(todo, at: 0)
            saveTodos()
        }
        dismissQuickAdd()
    }

    func dismissQuickAdd() {
        // Resign first responder before tearing down views
        panel.makeFirstResponder(nil)

        isQuickAddActive = false
        quickAddField = nil

        // Restore hidden views
        if let stack = minimizedMainStack {
            for v in stack.arrangedSubviews { v.isHidden = false }
        }
        updateTodosMiniList()

        if isExpanded { rebuildExpandedMain() }
    }

    /// Mark the currently-active block done via the global hotkey.
    /// Skips Break / Sleep blocks (no-op).
    func markCurrentBlockDoneViaHotkey() {
        guard let idx = currentBlockIndex else { return }
        let block = todayBlocks[idx]
        guard isCompletable(block) else { return }
        if !isDone(block) {
            setDone(block, true)
            tick()
        }
    }

}
