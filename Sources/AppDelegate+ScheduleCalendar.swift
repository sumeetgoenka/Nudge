//
//  AppDelegate+ScheduleCalendar.swift
//  AnayHub
//
//  Calendar-style Schedule view. Replaces the old day-pill approach.
//
//  Layout (top → bottom):
//    1. Header — "Your week, Anay." + week range subtitle
//       Edit + 📅 Pick Week + Today buttons on the right
//    2. Week strip — chevron < | Mon Tue Wed Thu Fri Sat Sun | chevron >
//       Each day shows the day name + the date number; today is tinted
//       blue, the selected date gets a filled background.
//    3. List — the blocks for the currently selected date.
//
//  All week math is anchored on the Monday of the viewed week, stored in
//  AppDelegate.scheduleViewedWeekStart.
//

import Cocoa

@MainActor
extension AppDelegate {

    func buildScheduleView() -> NSView {
        // ── Header
        let header = NSTextField(labelWithString: "Your week, Anay.")
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let subtitle = NSTextField(labelWithString: weekRangeSubtitle())
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 1

        // ── Right-side action buttons
        let editBtn = makeChromeButton(title: "Edit",
                                       action: #selector(enterScheduleEditor(_:)))
        let pickBtn = makeChromeButton(title: "📅",
                                       action: #selector(showWeekPicker(_:)))
        pickBtn.toolTip = "Pick a week"
        let todayBtn = makeChromeButton(title: "Today",
                                        action: #selector(jumpToTodayWeek(_:)))

        let headerRow = NSStackView(views: [headerStack, NSView(), editBtn, pickBtn, todayBtn])
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        // ── Week strip
        let weekStrip = buildWeekStrip()

        // ── Selected day list
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        scheduleListContainer = listContainer

        let stack = NSStackView(views: [headerRow, weekStrip, listContainer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        headerRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        headerRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        weekStrip.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        weekStrip.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        listContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        listContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        listContainer.bottomAnchor.constraint(equalTo: stack.bottomAnchor).isActive = true

        rebuildScheduleList()
        return stack
    }

    // MARK: - Header / chrome helpers

    func weekRangeSubtitle() -> String {
        let cal = Calendar.current
        let mon = scheduleViewedWeekStart
        let sun = cal.date(byAdding: .day, value: 6, to: mon) ?? mon
        let dayF = DateFormatter()
        dayF.dateFormat = "d MMM"
        let yearF = DateFormatter()
        yearF.dateFormat = "yyyy"
        return "Week of \(dayF.string(from: mon)) – \(dayF.string(from: sun)) · \(yearF.string(from: mon))"
    }

    func makeChromeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = Theme.surfaceHi.cgColor
        btn.attributedTitle = NSAttributedString(
            string: "  \(title)  ",
            attributes: [
                .foregroundColor: Theme.primary,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    // MARK: - Week strip

    func buildWeekStrip() -> NSView {
        let cal = Calendar.current
        let prev = NSButton(title: "‹", target: self, action: #selector(prevWeek(_:)))
        styleWeekChevron(prev)
        let next = NSButton(title: "›", target: self, action: #selector(nextWeek(_:)))
        styleWeekChevron(next)

        let daysRow = NSStackView()
        daysRow.orientation = .horizontal
        daysRow.distribution = .fillEqually
        daysRow.alignment = .centerY
        daysRow.spacing = 4

        scheduleDayButtons.removeAll()
        let dayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let todayKey = ScheduleStore.dateKey(cal.startOfDay(for: Date()))
        let selectedKey = scheduleSelectedDate.map { ScheduleStore.dateKey($0) }
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: i, to: scheduleViewedWeekStart) else { continue }
            let key = ScheduleStore.dateKey(date)
            let isSelected = (key == selectedKey)
            let isToday = (key == todayKey)
            let cell = makeWeekDayCell(name: dayShort[i],
                                       date: date,
                                       isSelected: isSelected,
                                       isToday: isToday)
            // We use the date offset (0..6) as the tag for click routing.
            cell.tag = i
            scheduleDayButtons[i] = cell
            daysRow.addArrangedSubview(cell)
        }

        let strip = NSStackView(views: [prev, daysRow, next])
        strip.orientation = .horizontal
        strip.alignment = .centerY
        strip.distribution = .fill
        strip.spacing = 8
        // Force the days row to consume all the space the chevrons don't use.
        daysRow.translatesAutoresizingMaskIntoConstraints = false
        daysRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
        daysRow.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        prev.setContentHuggingPriority(.required, for: .horizontal)
        next.setContentHuggingPriority(.required, for: .horizontal)
        return strip
    }

    private func styleWeekChevron(_ btn: NSButton) {
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = Theme.surface.cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 56).isActive = true
        btn.attributedTitle = NSAttributedString(
            string: btn.title,
            attributes: [
                .foregroundColor: Theme.secondary,
                .font: NSFont.systemFont(ofSize: 18, weight: .medium)
            ])
    }

    private func makeWeekDayCell(name: String, date: Date, isSelected: Bool, isToday: Bool) -> NSButton {
        let btn = NSButton(title: name, target: self, action: #selector(weekDayTapped(_:)))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let cal = Calendar.current
        let day = cal.component(.day, from: date)

        let bg: CGColor
        let dayColor: NSColor
        let numberColor: NSColor
        if isSelected {
            bg = Theme.accent.cgColor
            dayColor = Theme.secondary
            numberColor = Theme.primary
        } else if isToday {
            bg = Theme.accent.withAlphaComponent(0.18).cgColor
            dayColor = NSColor.systemBlue
            numberColor = NSColor.systemBlue
        } else {
            bg = Theme.surface.cgColor
            dayColor = Theme.tertiary
            numberColor = Theme.secondary
        }
        btn.layer?.backgroundColor = bg

        let combined = NSMutableAttributedString()
        combined.append(NSAttributedString(string: name + "\n", attributes: [
            .foregroundColor: dayColor,
            .font: NSFont.systemFont(ofSize: 9, weight: .heavy)
        ]))
        combined.append(NSAttributedString(string: "\(day)", attributes: [
            .foregroundColor: numberColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .heavy)
        ]))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 1
        combined.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: combined.length))
        btn.attributedTitle = combined
        return btn
    }

    // MARK: - Week navigation actions

    @objc func prevWeek(_ sender: Any?) {
        guard let new = Calendar.current.date(byAdding: .day, value: -7, to: scheduleViewedWeekStart) else { return }
        scheduleViewedWeekStart = new
        // No day highlighted on weeks that aren't the current week — only
        // the explicit "today" tint remains. The user can tap any day to
        // pick one.
        scheduleSelectedDate = defaultSelectionForViewedWeek()
        rebuildExpandedMain()
    }

    @objc func nextWeek(_ sender: Any?) {
        guard let new = Calendar.current.date(byAdding: .day, value: 7, to: scheduleViewedWeekStart) else { return }
        scheduleViewedWeekStart = new
        scheduleSelectedDate = defaultSelectionForViewedWeek()
        rebuildExpandedMain()
    }

    @objc func jumpToTodayWeek(_ sender: Any?) {
        let today = Calendar.current.startOfDay(for: Date())
        scheduleViewedWeekStart = Self.mondayOfWeek(containing: today)
        scheduleSelectedDate = today
        rebuildExpandedMain()
    }

    @objc func weekDayTapped(_ sender: NSButton) {
        let offset = sender.tag
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: scheduleViewedWeekStart) else { return }
        scheduleSelectedDate = Calendar.current.startOfDay(for: date)
        rebuildExpandedMain()
    }

    /// When you navigate to a different week, default the selection to today
    /// IF that week contains today. Otherwise return nil — no day highlighted.
    private func defaultSelectionForViewedWeek() -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let viewedMon = scheduleViewedWeekStart
        if let viewedSun = cal.date(byAdding: .day, value: 6, to: viewedMon),
           today >= viewedMon && today <= viewedSun {
            return today
        }
        return nil
    }

    // MARK: - Selected day list

    func rebuildScheduleList() {
        guard let container = scheduleListContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        // If nothing is selected, show a hint instead of an empty list.
        guard let day = scheduleSelectedDate else {
            let hint = NSTextField(labelWithString: "Tap a day above to see its schedule.")
            hint.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            hint.textColor = Theme.tertiary
            hint.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hint)
            NSLayoutConstraint.activate([
                hint.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
                hint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hint.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                container.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            ])
            return
        }

        let blocks = todaysSchedule(for: day)
        let completable = blocks.filter { isCompletable($0) }

        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        let dayTitle = NSTextField(labelWithString: f.string(from: day))
        dayTitle.font = NSFont.systemFont(ofSize: 14, weight: .heavy)
        dayTitle.textColor = Theme.primary

        let countLabel = NSTextField(labelWithString: "\(completable.count) tasks")
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = Theme.tertiary

        let titleStack = NSStackView(views: [dayTitle, countLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        for b in completable {
            let row = makeScheduleRow(b, on: day)
            list.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
        }

        let scroll = makeScroll(content: list)

        let inner = NSStackView(views: [titleStack, scroll])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: container.topAnchor),
            inner.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: inner.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: inner.trailingAnchor),
        ])
    }

    func makeScheduleRow(_ block: ScheduleBlock, on day: Date = Date()) -> NSView {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let timeStr = "\(f.string(from: block.start))–\(f.string(from: block.end))"
        let timeLabel = NSTextField(labelWithString: timeStr)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = Theme.tertiary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(timeLabel)

        let nameLabel = NSTextField(labelWithString: formatBlock(block))
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = Theme.secondary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(nameLabel)

        // Note button — pencil if no note, filled note if one exists.
        let hasNote = noteFor(block, on: day) != nil
        let noteBtn = NSButton(title: "", target: self,
                               action: #selector(scheduleNoteTapped(_:)))
        noteBtn.bezelStyle = .inline
        noteBtn.isBordered = false
        noteBtn.translatesAutoresizingMaskIntoConstraints = false
        // Encode the date + block index in a tag-friendly way: store on
        // the button via accessibilityValue (NSObject helper isn't great
        // here). Instead use a userInfo dict via associated objects? Easier:
        // route through a small helper that re-uses scheduleSelectedDate.
        noteBtn.attributedTitle = NSAttributedString(
            string: hasNote ? "📝" : "✎",
            attributes: [
                .foregroundColor: hasNote ? NSColor.systemYellow
                                          : Theme.muted,
                .font: NSFont.systemFont(ofSize: hasNote ? 13 : 14, weight: .regular)
            ])
        noteBtn.toolTip = noteFor(block, on: day) ?? "Add a note"
        // Tag = the block start time in minutes since midnight, used to
        // recover the block when the button fires.
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: block.start)
        noteBtn.tag = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        row.addSubview(noteBtn)

        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 6),
            timeLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 88),

            nameLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: noteBtn.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            noteBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            noteBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            noteBtn.widthAnchor.constraint(equalToConstant: 22),
            noteBtn.heightAnchor.constraint(equalToConstant: 22),
        ])
        return row
    }

    // MARK: - Week picker popup

    @objc func showWeekPicker(_ sender: Any?) {
        let cal = Calendar.current
        let anchor = scheduleSelectedDate ?? scheduleViewedWeekStart
        pickerYear = cal.component(.year, from: anchor)
        pickerMonth = cal.component(.month, from: anchor)
        pickerCursorDay = cal.component(.day, from: anchor)
        pickerStep = .day
        if weekPickerPanel == nil {
            weekPickerPanel = buildWeekPickerPanel()
        }
        guard let p = weekPickerPanel else { return }
        p.contentView = buildWeekPickerContent()
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let f = p.frame
        p.setFrame(NSRect(x: v.midX - f.width / 2,
                          y: v.midY - f.height / 2,
                          width: f.width, height: f.height), display: false)
        p.orderFrontRegardless()
        installPickerKeyMonitor()
    }

    private func reloadPickerContent() {
        guard let p = weekPickerPanel else { return }
        p.contentView = buildWeekPickerContent()
    }

    @objc func dismissWeekPicker(_ sender: Any?) {
        weekPickerPanel?.orderOut(nil)
        if let m = pickerKeyMonitor {
            NSEvent.removeMonitor(m)
            pickerKeyMonitor = nil
        }
        // Restore the HUD panel's normal "doesn't steal focus" behaviour.
        if !isEditingSchedule {
            panel.allowsKey = false
            panel.resignKey()
        }
    }

    /// Allow the HUD panel to become key while the picker is open so local
    /// keyboard monitors fire, then install the local monitor.
    private func installPickerKeyMonitor() {
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        if pickerKeyMonitor != nil { return }
        pickerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let p = self.weekPickerPanel,
                  p.isVisible else { return event }
            return self.handlePickerKey(event: event) ? nil : event
        }
    }

    private func handlePickerKey(event: NSEvent) -> Bool {
        let kc = event.keyCode
        // Esc → close
        if kc == 53 { dismissWeekPicker(nil); return true }
        // Enter / Return → commit cursor day on the day step
        if kc == 36 || kc == 76 {
            if pickerStep == .day {
                let cal = Calendar.current
                if let date = cal.date(from: DateComponents(year: pickerYear,
                                                             month: pickerMonth,
                                                             day: pickerCursorDay)) {
                    scheduleViewedWeekStart = AppDelegate.mondayOfWeek(containing: date)
                    scheduleSelectedDate = cal.startOfDay(for: date)
                    dismissWeekPicker(nil)
                    rebuildExpandedMain()
                }
            }
            return true
        }
        // Arrow keys — only on the day step
        guard pickerStep == .day else { return false }
        let cal = Calendar.current
        guard let cursorDate = cal.date(from: DateComponents(year: pickerYear,
                                                              month: pickerMonth,
                                                              day: pickerCursorDay)) else {
            return false
        }
        let delta: Int
        switch kc {
        case 123: delta = -1   // ←
        case 124: delta = 1    // →
        case 126: delta = -7   // ↑
        case 125: delta = 7    // ↓
        default: return false
        }
        guard let newDate = cal.date(byAdding: .day, value: delta, to: cursorDate) else { return true }
        pickerYear = cal.component(.year, from: newDate)
        pickerMonth = cal.component(.month, from: newDate)
        pickerCursorDay = cal.component(.day, from: newDate)
        reloadPickerContent()
        return true
    }

    private func buildWeekPickerPanel() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: 420, height: 480)
        let panel = NSPanel(contentRect: rect,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    private func buildWeekPickerContent() -> NSView {
        let rect = NSRect(x: 0, y: 0, width: 420, height: 480)
        let blur = NSVisualEffectView(frame: rect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        let border = CALayer()
        border.frame = blur.bounds
        border.cornerRadius = 14
        border.borderWidth = 0.5
        border.borderColor = Theme.border.cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(border)

        // ── Header row: back button (when applicable) + title + close
        let titleText: String
        switch pickerStep {
        case .year:  titleText = "Pick a year"
        case .month: titleText = "\(pickerYear)"
        case .day:   titleText = "\(monthName(pickerMonth)) \(pickerYear)"
        }
        let title = NSTextField(labelWithString: titleText)
        title.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        title.textColor = Theme.primary

        let backBtn = makePickerChromeButton(title: "‹  Back",
                                             action: #selector(pickerBackTapped(_:)))
        backBtn.isHidden = (pickerStep == .year)

        let closeBtn = makePickerChromeButton(title: "Close",
                                              action: #selector(dismissWeekPicker(_:)))

        let headerRow = NSStackView(views: [backBtn, title, NSView(), closeBtn])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // ── Body — depends on the step
        let body: NSView
        switch pickerStep {
        case .year:  body = buildYearGrid()
        case .month: body = buildMonthGrid()
        case .day:   body = buildDayGrid()
        }
        body.translatesAutoresizingMaskIntoConstraints = false

        let main = NSStackView(views: [headerRow, body])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 14
        main.translatesAutoresizingMaskIntoConstraints = false
        headerRow.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        headerRow.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        body.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        body.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true

        blur.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: blur.topAnchor, constant: 22),
            main.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 22),
            main.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -22),
            main.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -18),
        ])
        return blur
    }

    func makePickerChromeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = Theme.surfaceHi.cgColor
        btn.attributedTitle = NSAttributedString(
            string: "  \(title)  ",
            attributes: [
                .foregroundColor: Theme.secondary,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    func monthName(_ m: Int) -> String {
        let f = DateFormatter()
        return f.monthSymbols[m - 1]
    }

    func monthShort(_ m: Int) -> String {
        let f = DateFormatter()
        return f.shortMonthSymbols[m - 1]
    }

    @objc func pickerBackTapped(_ sender: Any?) {
        switch pickerStep {
        case .day:   pickerStep = .month
        case .month: pickerStep = .year
        case .year:  break
        }
        reloadPickerContent()
    }

    // MARK: - Year grid (2000 → 2100)

    private func buildYearGrid() -> NSView {
        let cols = 4
        let years = Array(2000...2100)
        let grid = makeGridStack(cols: cols)
        for y in years {
            let cell = makeYearCell(year: y)
            grid.addArrangedSubview(cell)
        }
        let scroll = makeScroll(content: grid)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: host.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            host.heightAnchor.constraint(equalToConstant: 380),
        ])
        return host
    }

    private func makeYearCell(year: Int) -> NSButton {
        let isCurrent = (year == Calendar.current.component(.year, from: Date()))
        let isPicked = (year == pickerYear)
        let btn = NSButton(title: "\(year)", target: self, action: #selector(yearCellTapped(_:)))
        btn.tag = year
        styleGridCell(btn, label: "\(year)", isCurrent: isCurrent, isSelected: isPicked, fontSize: 14, height: 50)
        return btn
    }

    @objc func yearCellTapped(_ sender: NSButton) {
        pickerYear = sender.tag
        pickerStep = .month
        reloadPickerContent()
    }

    // MARK: - Month grid (12 months)

    private func buildMonthGrid() -> NSView {
        let grid = makeGridStack(cols: 3)
        let cal = Calendar.current
        let todayMonth = cal.component(.month, from: Date())
        let todayYear = cal.component(.year, from: Date())
        for m in 1...12 {
            let isCurrent = (m == todayMonth && pickerYear == todayYear)
            let isPicked = (m == pickerMonth)
            let btn = NSButton(title: monthShort(m), target: self, action: #selector(monthCellTapped(_:)))
            btn.tag = m
            styleGridCell(btn, label: monthName(m), isCurrent: isCurrent, isSelected: isPicked, fontSize: 14, height: 70)
            grid.addArrangedSubview(btn)
        }
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: host.topAnchor),
            grid.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor),
            host.heightAnchor.constraint(equalToConstant: 380),
        ])
        return host
    }

    @objc func monthCellTapped(_ sender: NSButton) {
        pickerMonth = sender.tag
        pickerStep = .day
        reloadPickerContent()
    }

    // MARK: - Day grid (Apple Calendar style)

    private func buildDayGrid() -> NSView {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: 1)) else {
            return NSView()
        }
        let range = cal.range(of: .day, in: .month, for: firstOfMonth) ?? 1..<32
        let daysInMonth = range.count
        // weekday: 1=Sun..7=Sat. We want Mon-first, so leadingBlank for Sun = 6, Mon = 0, etc.
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (firstWeekday == 1) ? 6 : (firstWeekday - 2)

        // Top row: M T W T F S S labels
        let dayHeaderRow = NSStackView()
        dayHeaderRow.orientation = .horizontal
        dayHeaderRow.distribution = .fillEqually
        dayHeaderRow.alignment = .centerY
        dayHeaderRow.spacing = 4
        for label in ["M", "T", "W", "T", "F", "S", "S"] {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
            lbl.textColor = Theme.muted
            lbl.alignment = .center
            dayHeaderRow.addArrangedSubview(lbl)
        }

        // Day grid
        let grid = makeGridStack(cols: 7)
        let todayKey = ScheduleStore.dateKey(cal.startOfDay(for: Date()))
        let selectedKey = scheduleSelectedDate.map { ScheduleStore.dateKey($0) }

        for _ in 0..<leadingBlanks {
            grid.addArrangedSubview(NSView())
        }
        for d in 1...daysInMonth {
            guard let date = cal.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: d)) else { continue }
            let key = ScheduleStore.dateKey(date)
            let isToday = (key == todayKey)
            let isSelected = (key == selectedKey)
            let isCursor = (d == pickerCursorDay)
            let cell = NSButton(title: "\(d)", target: self, action: #selector(dayCellTapped(_:)))
            cell.tag = d
            styleDayGridCell(cell, day: d, isToday: isToday, isSelected: isSelected, isCursor: isCursor)
            grid.addArrangedSubview(cell)
        }

        let stack = NSStackView(views: [dayHeaderRow, grid])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        dayHeaderRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        dayHeaderRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        grid.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        grid.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        return stack
    }

    @objc func dayCellTapped(_ sender: NSButton) {
        let cal = Calendar.current
        guard let date = cal.date(from: DateComponents(year: pickerYear, month: pickerMonth, day: sender.tag)) else { return }
        scheduleViewedWeekStart = Self.mondayOfWeek(containing: date)
        scheduleSelectedDate = cal.startOfDay(for: date)
        dismissWeekPicker(nil)
        rebuildExpandedMain()
    }

    // MARK: - Grid layout helpers

    /// Builds an N-column grid out of nested horizontal stacks. We can't use
    /// NSGridView easily on Big Sur w/ stricter layout, so this is a row-based
    /// composer that AppKit can lay out cleanly.
    func makeGridStack(cols: Int) -> NSStackView {
        // The trick: we'll wrap items in batches of `cols` into horizontal
        // rows, but since this method just returns a vertical stack we need
        // to bridge by exposing addArrangedSubview that auto-batches.
        // Simpler: return a custom NSStackView subclass.
        let v = AutoGridStackView(cols: cols)
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 6
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func styleGridCell(_ btn: NSButton, label: String, isCurrent: Bool, isSelected: Bool, fontSize: CGFloat, height: CGFloat) {
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: height).isActive = true

        let bg: CGColor
        let fg: NSColor
        let weight: NSFont.Weight
        if isSelected {
            bg = Theme.accent.cgColor
            fg = Theme.primary
            weight = .heavy
        } else if isCurrent {
            bg = Theme.accent.withAlphaComponent(0.18).cgColor
            fg = NSColor.systemBlue
            weight = .semibold
        } else {
            bg = Theme.surface.cgColor
            fg = Theme.secondary
            weight = .medium
        }
        btn.layer?.backgroundColor = bg
        btn.attributedTitle = NSAttributedString(
            string: label,
            attributes: [
                .foregroundColor: fg,
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight)
            ])
    }

    func styleDayGridCell(_ btn: NSButton, day: Int, isToday: Bool, isSelected: Bool, isCursor: Bool) {
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let bg: CGColor
        let fg: NSColor
        let weight: NSFont.Weight
        if isSelected {
            bg = Theme.accent.cgColor
            fg = Theme.primary
            weight = .heavy
        } else if isToday {
            bg = Theme.accent.withAlphaComponent(0.20).cgColor
            fg = NSColor.systemBlue
            weight = .heavy
        } else {
            bg = Theme.surface.cgColor
            fg = Theme.secondary
            weight = .semibold
        }
        btn.layer?.backgroundColor = bg
        // Keyboard cursor — a white outline.
        if isCursor && !isSelected {
            btn.layer?.borderWidth = 1.5
            btn.layer?.borderColor = Theme.tertiary.cgColor
        } else {
            btn.layer?.borderWidth = 0
        }
        btn.attributedTitle = NSAttributedString(
            string: "\(day)",
            attributes: [
                .foregroundColor: fg,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: weight)
            ])
    }

    @objc func scheduleNoteTapped(_ sender: NSButton) {
        guard let day = scheduleSelectedDate else { return }
        let blocks = todaysSchedule(for: day).filter { isCompletable($0) }
        let cal = Calendar.current
        // Find the block whose start matches the tag (minutes since midnight).
        guard let block = blocks.first(where: { b in
            let c = cal.dateComponents([.hour, .minute], from: b.start)
            return ((c.hour ?? 0) * 60 + (c.minute ?? 0)) == sender.tag
        }) else { return }
        showBlockNoteEditor(for: block, on: day)
    }
}
