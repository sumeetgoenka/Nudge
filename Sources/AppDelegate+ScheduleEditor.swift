//
//  AppDelegate+ScheduleEditor.swift
//  Nudge
//
//  In-app schedule editor accessible from the expanded Schedule view.
//
//  Two tabs:
//    - One-off: edits a single calendar date (the upcoming instance of the
//      selected weekday). Saves to ScheduleStore.dateOverrides.
//    - Permanent: edits the weekly base for the selected weekday. Saves to
//      ScheduleStore.weeklyBase.
//
//  Validation: every save runs ScheduleStore.validate(_:). Day must be
//  gap-free from 00:00 to 24:00; the user gets a clear error if not.
//
//  Navigation guard: switching day or tab while there are unsaved changes
//  prompts an NSAlert offering Save / Discard / Cancel.
//

import Cocoa

@MainActor
extension AppDelegate {

    // MARK: - Entering / exiting edit mode

    @objc func enterScheduleEditor(_ sender: Any?) {
        isEditingSchedule = true
        editorTab = .oneoff
        editorWeekday = scheduleSelectedWeekday
        loadEditorBlocks()
        rebuildExpandedMain()
        // Allow keyboard input into NSTextFields. The panel normally refuses
        // to become key so it doesn't steal focus during HUD use.
        panel.allowsKey = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func exitScheduleEditor() {
        isEditingSchedule = false
        editorBlocks.removeAll()
        editorBaseline.removeAll()
        editorRowsContainer = nil
        editorErrorLabel = nil
        editorTabButtons.removeAll()
        editorDayButtons.removeAll()
        editorOverrideBadge = nil
        // Drop keyboard focus and revert to normal HUD behavior.
        panel.allowsKey = false
        panel.resignKey()
        NSApp.setActivationPolicy(.accessory)
        rebuildExpandedMain()
    }

    // MARK: - Date helpers

    /// The calendar date that the One-off tab is editing for the currently
    /// selected weekday: today if the weekday matches, otherwise the next
    /// upcoming instance of that weekday.
    func editorTargetDate(for weekday: Int) -> Date {
        let cal = Calendar.current
        let today = Date()
        let todayWd = cal.component(.weekday, from: today)
        if weekday == todayWd { return cal.startOfDay(for: today) }
        // Find the next upcoming date with this weekday (1..6 days ahead).
        for offset in 1...7 {
            if let candidate = cal.date(byAdding: .day, value: offset, to: today),
               cal.component(.weekday, from: candidate) == weekday {
                return cal.startOfDay(for: candidate)
            }
        }
        return cal.startOfDay(for: today)
    }

    /// Pull the working copy of blocks from the store based on the current
    /// tab + weekday. Snapshots into editorBaseline so we can detect dirty.
    func loadEditorBlocks() {
        let store = ScheduleStore.shared
        switch editorTab {
        case .oneoff:
            let date = editorTargetDate(for: editorWeekday)
            if let override = store.dateOverride(for: date) {
                editorBlocks = override
            } else {
                // No override yet — start from the weekly base as a template.
                editorBlocks = store.weeklyBase(for: editorWeekday)
            }
        case .permanent:
            editorBlocks = store.weeklyBase(for: editorWeekday)
        }
        editorBaseline = editorBlocks
    }

    /// Have the working blocks diverged from the last saved/loaded baseline?
    var editorIsDirty: Bool {
        return editorBlocks != editorBaseline
    }

    // MARK: - View

    func buildScheduleEditorView() -> NSView {
        let header = NSTextField(labelWithString: "Edit Schedule")
        header.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        header.textColor = .white

        let cancelBtn = makeEditorChromeButton(title: "Cancel",
                                               action: #selector(editorCancelTapped(_:)))
        editorCancelButton = cancelBtn
        let saveBtn = makeEditorChromeButton(title: "Save",
                                             action: #selector(editorSaveTapped(_:)))
        saveBtn.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.85).cgColor

        let headerRow = NSStackView(views: [header, NSView(), cancelBtn, saveBtn])
        headerRow.orientation = .horizontal
        headerRow.distribution = .fill
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        // Tab bar
        let tabRow = buildEditorTabBar()

        // Day picker
        let dayRow = buildEditorDayPicker()

        // Override badge ("Override active for 2026-04-08")
        let badge = NSTextField(labelWithString: "")
        badge.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        badge.textColor = NSColor.systemOrange
        editorOverrideBadge = badge

        // Validation error label
        let errLabel = NSTextField(labelWithString: "")
        errLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        errLabel.textColor = NSColor.systemRed
        errLabel.lineBreakMode = .byWordWrapping
        errLabel.maximumNumberOfLines = 3
        errLabel.preferredMaxLayoutWidth = 360
        editorErrorLabel = errLabel

        // Rows container (filled by rebuildEditorRows)
        let rowsContainer = NSView()
        rowsContainer.translatesAutoresizingMaskIntoConstraints = false
        editorRowsContainer = rowsContainer

        // + Add block button
        let addBtn = NSButton(title: "+ Add block", target: self,
                              action: #selector(editorAddBlockTapped(_:)))
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.attributedTitle = NSAttributedString(
            string: "+ Add block",
            attributes: [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ])

        let stack = NSStackView(views: [headerRow, tabRow, dayRow, badge, errLabel, rowsContainer, addBtn])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        headerRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        headerRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        rowsContainer.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        rowsContainer.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        styleEditorTabButtons()
        styleEditorDayButtons()
        refreshEditorOverrideBadge()
        rebuildEditorRows()
        refreshEditorCancelButton()

        return stack
    }

    /// Updates the secondary button between "Cancel" (when there are unsaved
    /// changes — reverts them) and "Exit" (clean state — closes the editor).
    func refreshEditorCancelButton() {
        guard let btn = editorCancelButton else { return }
        let title = editorIsDirty ? "Cancel" : "Exit"
        btn.title = title
        btn.attributedTitle = NSAttributedString(
            string: "  \(title)  ",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
    }

    // MARK: - Editor sub-builders

    func makeEditorChromeButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        btn.attributedTitle = NSAttributedString(
            string: "  \(title)  ",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    func buildEditorTabBar() -> NSView {
        editorTabButtons.removeAll()
        let oneoff = NSButton(title: "One-off", target: self,
                              action: #selector(editorTabTapped(_:)))
        oneoff.tag = 0
        let permanent = NSButton(title: "Permanent", target: self,
                                 action: #selector(editorTabTapped(_:)))
        permanent.tag = 1
        for btn in [oneoff, permanent] {
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        editorTabButtons[.oneoff] = oneoff
        editorTabButtons[.permanent] = permanent
        let row = NSStackView(views: [oneoff, permanent])
        row.orientation = .horizontal
        row.spacing = 6
        return row
    }

    func styleEditorTabButtons() {
        for (tab, btn) in editorTabButtons {
            let active = (tab == editorTab)
            btn.layer?.backgroundColor = active
                ? NSColor.systemBlue.withAlphaComponent(0.85).cgColor
                : NSColor.white.withAlphaComponent(0.10).cgColor
            btn.attributedTitle = NSAttributedString(
                string: "  \(btn.title)  ",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .medium)
                ])
        }
    }

    func buildEditorDayPicker() -> NSView {
        editorDayButtons.removeAll()
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
        let dayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        for (i, wd) in weekdayOrder.enumerated() {
            let btn = NSButton(title: dayShort[i], target: self,
                               action: #selector(editorDayTapped(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.tag = wd
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            editorDayButtons[wd] = btn
            row.addArrangedSubview(btn)
        }
        return row
    }

    func styleEditorDayButtons() {
        for (wd, btn) in editorDayButtons {
            let active = (wd == editorWeekday)
            btn.layer?.backgroundColor = active
                ? NSColor.white.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
            btn.attributedTitle = NSAttributedString(
                string: btn.title,
                attributes: [
                    .foregroundColor: active ? NSColor.white : NSColor.white.withAlphaComponent(0.55),
                    .font: NSFont.systemFont(ofSize: 12, weight: active ? .semibold : .regular)
                ])
        }
    }

    func refreshEditorOverrideBadge() {
        guard let badge = editorOverrideBadge else { return }
        switch editorTab {
        case .oneoff:
            let date = editorTargetDate(for: editorWeekday)
            let f = DateFormatter()
            f.dateFormat = "EEEE, d MMM yyyy"
            let label = "Editing \(f.string(from: date))"
            if ScheduleStore.shared.hasOverride(for: date) {
                badge.stringValue = "\(label) (override active)"
                badge.textColor = NSColor.systemOrange
            } else {
                badge.stringValue = "\(label) (no override yet)"
                badge.textColor = NSColor.white.withAlphaComponent(0.55)
            }
        case .permanent:
            let names = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
                         5: "Thursday", 6: "Friday", 7: "Saturday"]
            badge.stringValue = "Editing \(names[editorWeekday] ?? "") (every week)"
            badge.textColor = NSColor.white.withAlphaComponent(0.65)
        }
    }

    // MARK: - Row list

    func rebuildEditorRows() {
        guard let container = editorRowsContainer else { return }
        container.subviews.forEach { $0.removeFromSuperview() }

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4
        list.translatesAutoresizingMaskIntoConstraints = false
        for (i, _) in editorBlocks.enumerated() {
            let row = makeEditorRow(index: i)
            list.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
        }

        let scroll = makeScroll(content: list)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    func makeEditorRow(index: Int) -> NSView {
        let block = editorBlocks[index]
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let startField = ClickToFocusTextField(string: block.startStr)
        let endField = ClickToFocusTextField(string: block.endStr)
        let nameField = ClickToFocusTextField(string: block.name)
        for f in [startField, endField, nameField] {
            f.font = NSFont.systemFont(ofSize: 12)
            f.bezelStyle = .roundedBezel
            f.focusRingType = .none
            f.translatesAutoresizingMaskIntoConstraints = false
            f.delegate = self
            f.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        startField.identifier = NSUserInterfaceItemIdentifier("editorStart-\(index)")
        endField.identifier   = NSUserInterfaceItemIdentifier("editorEnd-\(index)")
        nameField.identifier  = NSUserInterfaceItemIdentifier("editorName-\(index)")

        // Compulsory checkbox — toggles whether this block is tickable /
        // counts toward completion. Tooltip explains the meaning.
        let compBox = NSButton(checkboxWithTitle: "", target: self,
                               action: #selector(editorCompulsoryToggled(_:)))
        compBox.state = block.effectiveCompulsory ? .on : .off
        compBox.tag = index
        compBox.toolTip = "Compulsory — counts toward your daily completion %"
        compBox.translatesAutoresizingMaskIntoConstraints = false

        let delBtn = NSButton(title: "×", target: self,
                              action: #selector(editorDeleteRowTapped(_:)))
        delBtn.bezelStyle = .inline
        delBtn.isBordered = false
        delBtn.tag = index
        delBtn.translatesAutoresizingMaskIntoConstraints = false
        delBtn.attributedTitle = NSAttributedString(
            string: "×",
            attributes: [
                .foregroundColor: NSColor.systemRed.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold)
            ])
        delBtn.widthAnchor.constraint(equalToConstant: 22).isActive = true
        delBtn.heightAnchor.constraint(equalToConstant: 22).isActive = true

        row.addSubview(startField)
        row.addSubview(endField)
        row.addSubview(nameField)
        row.addSubview(compBox)
        row.addSubview(delBtn)
        NSLayoutConstraint.activate([
            startField.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            startField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            startField.widthAnchor.constraint(equalToConstant: 60),

            endField.leadingAnchor.constraint(equalTo: startField.trailingAnchor, constant: 4),
            endField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            endField.widthAnchor.constraint(equalToConstant: 60),

            nameField.leadingAnchor.constraint(equalTo: endField.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: compBox.leadingAnchor, constant: -8),

            compBox.trailingAnchor.constraint(equalTo: delBtn.leadingAnchor, constant: -6),
            compBox.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            delBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            delBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    @objc func editorCompulsoryToggled(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < editorBlocks.count else { return }
        editorBlocks[i].compulsory = (sender.state == .on)
        refreshEditorCancelButton()
    }

    // MARK: - Add / delete

    @objc func editorAddBlockTapped(_ sender: NSButton) {
        // Default new block: a 30-min slot starting where the previous block
        // ended, or 00:00 if the list is empty.
        let lastEnd = editorBlocks.last?.endStr ?? "00:00"
        var startMin = ScheduleStore.minutes(of: lastEnd) ?? 0
        if startMin >= 24 * 60 { startMin = 23 * 60 + 30 }
        let endMin = min(24 * 60, startMin + 30)
        let new = EditableBlock(
            startStr: ScheduleStore.formatMinutes(startMin),
            endStr: ScheduleStore.formatMinutes(endMin),
            name: "New block")
        editorBlocks.append(new)
        rebuildEditorRows()
        refreshEditorCancelButton()
    }

    @objc func editorDeleteRowTapped(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < editorBlocks.count else { return }
        editorBlocks.remove(at: i)
        rebuildEditorRows()
        refreshEditorCancelButton()
    }

    // MARK: - Save / cancel

    @objc func editorSaveTapped(_ sender: Any?) {
        do {
            switch editorTab {
            case .oneoff:
                let date = editorTargetDate(for: editorWeekday)
                try ScheduleStore.shared.saveDateOverride(editorBlocks, for: date)
            case .permanent:
                try ScheduleStore.shared.saveWeeklyBase(editorBlocks, for: editorWeekday)
            }
            // Sync the live schedule and refresh related UI.
            editorBaseline = editorBlocks
            recomputeCurrentBlock(force: true)
            tick()
            refreshEditorOverrideBadge()
            refreshEditorCancelButton()
            showEditorStatus("✓ Saved", color: NSColor.systemGreen)
        } catch let err as ScheduleValidationError {
            showEditorStatus(err.description, color: NSColor.systemRed)
        } catch {
            showEditorStatus("Couldn't save: \(error.localizedDescription)",
                             color: NSColor.systemRed)
        }
    }

    /// Set the status / error label and auto-clear after a couple seconds for
    /// success messages. Errors stay until the next save attempt.
    private func showEditorStatus(_ text: String, color: NSColor) {
        guard let label = editorErrorLabel else { return }
        label.stringValue = text
        label.textColor = color
        editorStatusClearTimer?.invalidate()
        if color == NSColor.systemGreen {
            editorStatusClearTimer = Timer.scheduledTimer(withTimeInterval: 2.0,
                                                          repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.editorErrorLabel?.stringValue = ""
                }
            }
        }
    }

    @objc func editorCancelTapped(_ sender: Any?) {
        if editorIsDirty {
            // Cancel = revert unsaved changes back to last saved baseline.
            // Stay in the editor so the user can keep working.
            editorBlocks = editorBaseline
            rebuildEditorRows()
            refreshEditorCancelButton()
            showEditorStatus("Reverted unsaved changes",
                             color: NSColor.white.withAlphaComponent(0.7))
            // Manually trigger the auto-clear (showEditorStatus only auto-clears green).
            editorStatusClearTimer?.invalidate()
            editorStatusClearTimer = Timer.scheduledTimer(withTimeInterval: 2.0,
                                                          repeats: false) { [weak self] _ in
                Task { @MainActor in self?.editorErrorLabel?.stringValue = "" }
            }
        } else {
            // Clean state — close the editor entirely.
            exitScheduleEditor()
        }
    }

    // MARK: - Tab / day switching (with dirty guard)

    @objc func editorTabTapped(_ sender: NSButton) {
        let target: ScheduleEditorTab = (sender.tag == 0) ? .oneoff : .permanent
        if target == editorTab { return }
        switchEditorContext { [weak self] in
            self?.editorTab = target
            self?.loadEditorBlocks()
            self?.rebuildExpandedMain()
        }
    }

    @objc func editorDayTapped(_ sender: NSButton) {
        let target = sender.tag
        if target == editorWeekday { return }
        switchEditorContext { [weak self] in
            self?.editorWeekday = target
            self?.loadEditorBlocks()
            self?.rebuildExpandedMain()
        }
    }

    /// Run `apply` if there are no unsaved changes; otherwise prompt the user.
    private func switchEditorContext(_ apply: @escaping () -> Void) {
        if editorIsDirty {
            promptUnsavedChanges(onSave: { [weak self] in
                self?.editorSaveTapped(nil)
                if (self?.editorErrorLabel?.stringValue ?? "").isEmpty {
                    apply()
                }
            }, onDiscard: {
                apply()
            })
        } else {
            apply()
        }
    }

    private func promptUnsavedChanges(onSave: @escaping () -> Void,
                                      onDiscard: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Save changes to this day first?"
        alert.informativeText = "You've made edits that aren't saved yet. You can't move on until you save them or discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  onSave()
        case .alertSecondButtonReturn: onDiscard()
        default: break  // Cancel — stay put
        }
    }
}

// MARK: - Text field delegate (capture edits to the working block list)

extension AppDelegate: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        guard isEditingSchedule,
              let field = obj.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let index = Int(parts[1]),
              index >= 0, index < editorBlocks.count else { return }
        var block = editorBlocks[index]
        switch String(parts[0]) {
        case "editorStart": block.startStr = field.stringValue
        case "editorEnd":   block.endStr   = field.stringValue
        case "editorName":  block.name     = field.stringValue
        default: break
        }
        editorBlocks[index] = block
        refreshEditorCancelButton()
    }
}
