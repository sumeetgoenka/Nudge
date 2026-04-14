//
//  AppDelegate+More.swift
//  Nudge
//
//  The "More" sidebar tab — currently houses the Complete Quit button.
//  Future home for settings (sounds, notification toggles, theme, etc.).
//

import Cocoa

@MainActor
extension AppDelegate {

    func buildMoreView() -> NSView {
        let header = NSTextField(labelWithString: "More")
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let subtitle = NSTextField(labelWithString: "Controls")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        // ── Light-mood toggle card ──────────────────────────────────
        let moodCard = makeMoreCard()
        moodCard.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let moodTitle = NSTextField(labelWithString: "Light Mood")
        moodTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        moodTitle.textColor = Theme.primary

        let moodBlurb = NSTextField(labelWithString: "Switches the HUD to a softer, less moody frosted background. Easier on the eyes for long sessions.")
        moodBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        moodBlurb.textColor = Theme.tertiary
        moodBlurb.lineBreakMode = .byWordWrapping
        moodBlurb.maximumNumberOfLines = 2
        moodBlurb.preferredMaxLayoutWidth = 380

        let moodToggle = NSButton(checkboxWithTitle: "  Enable Light Mood",
                                  target: self,
                                  action: #selector(lightMoodToggled(_:)))
        moodToggle.state = lightMoodEnabled ? .on : .off
        moodToggle.contentTintColor = Theme.primary
        moodToggle.translatesAutoresizingMaskIntoConstraints = false

        let moodStack = NSStackView(views: [moodTitle, moodBlurb, moodToggle])
        moodStack.orientation = .vertical
        moodStack.alignment = .leading
        moodStack.spacing = 6
        moodStack.translatesAutoresizingMaskIntoConstraints = false
        moodCard.addSubview(moodStack)
        NSLayoutConstraint.activate([
            moodStack.topAnchor.constraint(equalTo: moodCard.topAnchor, constant: 14),
            moodStack.leadingAnchor.constraint(equalTo: moodCard.leadingAnchor, constant: 16),
            moodStack.trailingAnchor.constraint(equalTo: moodCard.trailingAnchor, constant: -16),
            moodStack.bottomAnchor.constraint(lessThanOrEqualTo: moodCard.bottomAnchor, constant: -10),
        ])

        // ── Widget mode toggle card ─────────────────────────────────
        let modeCard = makeMoreCard()
        modeCard.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let modeTitle = NSTextField(labelWithString: "Widget Mode")
        modeTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        modeTitle.textColor = Theme.primary

        let modeBlurb = NSTextField(labelWithString: "Choose what your floating widget shows: your daily schedule or your todo list.")
        modeBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        modeBlurb.textColor = Theme.tertiary
        modeBlurb.lineBreakMode = .byWordWrapping
        modeBlurb.maximumNumberOfLines = 2
        modeBlurb.preferredMaxLayoutWidth = 380

        let scheduleRadio = NSButton(radioButtonWithTitle: "  Schedule", target: self, action: #selector(widgetModeChanged(_:)))
        scheduleRadio.tag = 0
        scheduleRadio.state = minimizedViewMode == "schedule" ? .on : .off
        scheduleRadio.contentTintColor = Theme.primary

        let todosRadio = NSButton(radioButtonWithTitle: "  Todos", target: self, action: #selector(widgetModeChanged(_:)))
        todosRadio.tag = 1
        todosRadio.state = minimizedViewMode == "todos" ? .on : .off
        todosRadio.contentTintColor = Theme.primary

        let radioRow = NSStackView(views: [scheduleRadio, todosRadio])
        radioRow.orientation = .horizontal
        radioRow.spacing = 20

        let modeStack = NSStackView(views: [modeTitle, modeBlurb, radioRow])
        modeStack.orientation = .vertical
        modeStack.alignment = .leading
        modeStack.spacing = 6
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeCard.addSubview(modeStack)
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: modeCard.topAnchor, constant: 14),
            modeStack.leadingAnchor.constraint(equalTo: modeCard.leadingAnchor, constant: 16),
            modeStack.trailingAnchor.constraint(equalTo: modeCard.trailingAnchor, constant: -16),
            modeStack.bottomAnchor.constraint(lessThanOrEqualTo: modeCard.bottomAnchor, constant: -10),
        ])

        // ── Water Reminders toggle card ─────────────────────────────
        let waterCard = makeMoreCard()
        waterCard.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let waterTitle = NSTextField(labelWithString: "Water Reminders")
        waterTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        waterTitle.textColor = Theme.primary

        let waterBlurb = NSTextField(labelWithString: "Hourly reminders to drink 250ml of water. Keeps you hydrated throughout the day.")
        waterBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        waterBlurb.textColor = Theme.tertiary
        waterBlurb.lineBreakMode = .byWordWrapping
        waterBlurb.maximumNumberOfLines = 2
        waterBlurb.preferredMaxLayoutWidth = 380

        let waterToggle = NSButton(checkboxWithTitle: "  Enable Water Reminders",
                                   target: self,
                                   action: #selector(waterRemindersToggled(_:)))
        waterToggle.state = waterRemindersEnabled ? .on : .off
        waterToggle.contentTintColor = Theme.primary
        waterToggle.translatesAutoresizingMaskIntoConstraints = false

        let waterStack = NSStackView(views: [waterTitle, waterBlurb, waterToggle])
        waterStack.orientation = .vertical
        waterStack.alignment = .leading
        waterStack.spacing = 6
        waterStack.translatesAutoresizingMaskIntoConstraints = false
        waterCard.addSubview(waterStack)
        NSLayoutConstraint.activate([
            waterStack.topAnchor.constraint(equalTo: waterCard.topAnchor, constant: 14),
            waterStack.leadingAnchor.constraint(equalTo: waterCard.leadingAnchor, constant: 16),
            waterStack.trailingAnchor.constraint(equalTo: waterCard.trailingAnchor, constant: -16),
            waterStack.bottomAnchor.constraint(lessThanOrEqualTo: waterCard.bottomAnchor, constant: -10),
        ])

        // ── 20-20-20 Eye Break toggle card ──────────────────────────
        let eyeCard = makeMoreCard()
        eyeCard.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let eyeTitle = NSTextField(labelWithString: "20-20-20 Rule")
        eyeTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        eyeTitle.textColor = Theme.primary

        let eyeBlurb = NSTextField(labelWithString: "Every 20 minutes, look at something 20 feet away for 20 seconds. Reduces eye strain from screens.")
        eyeBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        eyeBlurb.textColor = Theme.tertiary
        eyeBlurb.lineBreakMode = .byWordWrapping
        eyeBlurb.maximumNumberOfLines = 2
        eyeBlurb.preferredMaxLayoutWidth = 380

        let eyeToggle = NSButton(checkboxWithTitle: "  Enable Screen Time Reminders",
                                 target: self,
                                 action: #selector(eyeBreakToggled(_:)))
        eyeToggle.state = eyeBreakEnabled ? .on : .off
        eyeToggle.contentTintColor = Theme.primary
        eyeToggle.translatesAutoresizingMaskIntoConstraints = false

        let eyeStack = NSStackView(views: [eyeTitle, eyeBlurb, eyeToggle])
        eyeStack.orientation = .vertical
        eyeStack.alignment = .leading
        eyeStack.spacing = 6
        eyeStack.translatesAutoresizingMaskIntoConstraints = false
        eyeCard.addSubview(eyeStack)
        NSLayoutConstraint.activate([
            eyeStack.topAnchor.constraint(equalTo: eyeCard.topAnchor, constant: 14),
            eyeStack.leadingAnchor.constraint(equalTo: eyeCard.leadingAnchor, constant: 16),
            eyeStack.trailingAnchor.constraint(equalTo: eyeCard.trailingAnchor, constant: -16),
            eyeStack.bottomAnchor.constraint(lessThanOrEqualTo: eyeCard.bottomAnchor, constant: -10),
        ])

        // ── Snap to Corner toggle card ───────────────────────────────
        let snapCard = makeMoreCard()
        snapCard.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let snapTitle = NSTextField(labelWithString: "Snap to Corner")
        snapTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        snapTitle.textColor = Theme.primary

        let snapBlurb = NSTextField(labelWithString: "When enabled, the widget snaps to the nearest screen corner after dragging. Disable to place it anywhere.")
        snapBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        snapBlurb.textColor = Theme.tertiary
        snapBlurb.lineBreakMode = .byWordWrapping
        snapBlurb.maximumNumberOfLines = 2
        snapBlurb.preferredMaxLayoutWidth = 380

        let snapToggle = NSButton(checkboxWithTitle: "  Disable Snap to Corner",
                                  target: self,
                                  action: #selector(snapToCornerToggled(_:)))
        snapToggle.state = snapToCornerDisabled ? .on : .off
        snapToggle.contentTintColor = Theme.primary
        snapToggle.translatesAutoresizingMaskIntoConstraints = false

        let snapStack = NSStackView(views: [snapTitle, snapBlurb, snapToggle])
        snapStack.orientation = .vertical
        snapStack.alignment = .leading
        snapStack.spacing = 6
        snapStack.translatesAutoresizingMaskIntoConstraints = false
        snapCard.addSubview(snapStack)
        NSLayoutConstraint.activate([
            snapStack.topAnchor.constraint(equalTo: snapCard.topAnchor, constant: 14),
            snapStack.leadingAnchor.constraint(equalTo: snapCard.leadingAnchor, constant: 16),
            snapStack.trailingAnchor.constraint(equalTo: snapCard.trailingAnchor, constant: -16),
            snapStack.bottomAnchor.constraint(lessThanOrEqualTo: snapCard.bottomAnchor, constant: -10),
        ])

        // ── Accessibility card ────────────────────────────────────────
        let accessCard = makeMoreCard()
        accessCard.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let accessTitle = NSTextField(labelWithString: "Accessibility")
        accessTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        accessTitle.textColor = Theme.primary

        let accessBlurb = NSTextField(labelWithString: "Required for global keyboard shortcuts (⌃⌥N quick-add) to work from any app. Opens System Settings.")
        accessBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        accessBlurb.textColor = Theme.tertiary
        accessBlurb.lineBreakMode = .byWordWrapping
        accessBlurb.maximumNumberOfLines = 3
        accessBlurb.preferredMaxLayoutWidth = 380

        let accessBtn = NSButton(title: "Open Accessibility Settings", target: self,
                                 action: #selector(openAccessibilitySettings(_:)))
        accessBtn.bezelStyle = .inline
        accessBtn.isBordered = false
        accessBtn.wantsLayer = true
        accessBtn.layer?.cornerRadius = 7
        accessBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        accessBtn.attributedTitle = NSAttributedString(
            string: "  Open Accessibility Settings  ",
            attributes: [
                .foregroundColor: Theme.primary,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        accessBtn.translatesAutoresizingMaskIntoConstraints = false
        accessBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let accessStack = NSStackView(views: [accessTitle, accessBlurb, accessBtn])
        accessStack.orientation = .vertical
        accessStack.alignment = .leading
        accessStack.spacing = 6
        accessStack.translatesAutoresizingMaskIntoConstraints = false
        accessCard.addSubview(accessStack)
        NSLayoutConstraint.activate([
            accessStack.topAnchor.constraint(equalTo: accessCard.topAnchor, constant: 14),
            accessStack.leadingAnchor.constraint(equalTo: accessCard.leadingAnchor, constant: 16),
            accessStack.trailingAnchor.constraint(equalTo: accessCard.trailingAnchor, constant: -16),
            accessStack.bottomAnchor.constraint(lessThanOrEqualTo: accessCard.bottomAnchor, constant: -10),
        ])

        // ── Updates card ────────────────────────────────────────────
        let updateCard = makeMoreCard()
        updateCard.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let updateTitle = NSTextField(labelWithString: "Updates")
        updateTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        updateTitle.textColor = .white

        let updateBtn = NSButton(title: "Check for Updates", target: self,
                                  action: #selector(checkForUpdatesTapped(_:)))
        updateBtn.bezelStyle = .rounded
        updateBtn.wantsLayer = true
        updateBtn.layer?.cornerRadius = 8
        updateBtn.layer?.backgroundColor = Theme.surface.cgColor
        updateBtn.attributedTitle = NSAttributedString(
            string: "  Check for Updates  ",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ])

        let updateStack = NSStackView(views: [updateTitle, updateBtn])
        updateStack.orientation = .vertical
        updateStack.alignment = .leading
        updateStack.spacing = 10
        updateStack.translatesAutoresizingMaskIntoConstraints = false
        updateCard.addSubview(updateStack)
        NSLayoutConstraint.activate([
            updateStack.topAnchor.constraint(equalTo: updateCard.topAnchor, constant: 14),
            updateStack.leadingAnchor.constraint(equalTo: updateCard.leadingAnchor, constant: 16),
            updateStack.trailingAnchor.constraint(equalTo: updateCard.trailingAnchor, constant: -16),
        ])

        // ── Master stack ─────────────────────────────────────────────
        let main = NSStackView(views: [headerStack, modeCard, moodCard, snapCard, waterCard, eyeCard, accessCard, updateCard])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 16
        main.translatesAutoresizingMaskIntoConstraints = false
        modeCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        modeCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        moodCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        moodCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        snapCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        snapCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        waterCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        waterCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        eyeCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        eyeCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        accessCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        accessCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        updateCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        updateCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true

        let scroll = makeScroll(content: main)
        return scroll
    }

    @objc func widgetModeChanged(_ sender: NSButton) {
        let newMode = sender.tag == 0 ? "schedule" : "todos"
        guard newMode != minimizedViewMode else { return }
        saveMinimizedViewMode(newMode)
        // The minimized view will be rebuilt when the user collapses
        // the expanded panel — no need to rebuild it now.
    }

    @objc func waterRemindersToggled(_ sender: NSButton) {
        waterRemindersEnabled = (sender.state == .on)
        UserDefaults.standard.set(waterRemindersEnabled, forKey: "Nudge.waterRemindersEnabled")
        if waterRemindersEnabled {
            loadWaterReminderState()
        }
    }

    @objc func eyeBreakToggled(_ sender: NSButton) {
        eyeBreakEnabled = (sender.state == .on)
        UserDefaults.standard.set(eyeBreakEnabled, forKey: "Nudge.eyeBreakEnabled")
        if eyeBreakEnabled {
            laptopOpenSeconds = 0
        }
    }

    @objc func openAccessibilitySettings(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func snapToCornerToggled(_ sender: NSButton) {
        snapToCornerDisabled = (sender.state == .on)
        UserDefaults.standard.set(snapToCornerDisabled, forKey: "Nudge.snapToCornerDisabled")
    }

    @objc func lightMoodToggled(_ sender: NSButton) {
        lightMoodEnabled = (sender.state == .on)
        applyLightMoodTheme()
    }

    @objc func checkForUpdatesTapped(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }

    private func makeMoreCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = Theme.surface.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

}
