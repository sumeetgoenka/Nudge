//
//  AppDelegate+Onboarding.swift
//  Nudge
//
//  First-launch onboarding: collects the user's name and lets them choose
//  their preferred minimized view mode (schedule or todos).
//

import Cocoa

/// A simple key-capable panel for onboarding — no HUDPanel tricks needed.
/// The app is promoted to .regular for the entire onboarding flow so
/// keyboard input just works.
final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
extension AppDelegate {

    func showOnboarding() {
        // Promote to .regular so the app can receive keyboard input.
        // This makes it appear in the dock — that's fine during onboarding.
        NSApp.setActivationPolicy(.regular)

        let panel = buildOnboardingPanel()
        onboardingPanel = panel

        // Center on the main screen
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let v = screen.visibleFrame
        let f = panel.frame
        let x = v.midX - f.width / 2
        let y = v.midY - f.height / 2
        panel.setFrame(NSRect(x: x, y: y, width: f.width, height: f.height), display: false)

        // Activate the app and make the panel key so text fields work
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func buildOnboardingPanel() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: 420, height: 460)
        let panel = OnboardingPanel(contentRect: rect,
                            styleMask: [.borderless],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Frosted background
        let blur = NSVisualEffectView(frame: rect)
        blur.material = .hudWindow
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        // Hairline border
        let border = CALayer()
        border.frame = blur.bounds
        border.cornerRadius = 16
        border.borderWidth = 0.5
        border.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(border)

        let content = buildOnboardingStep1()
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: blur.topAnchor, constant: 32),
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -32),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -28),
        ])

        panel.contentView = blur
        return panel
    }

    // MARK: - Step 1: Welcome + Name

    private func buildOnboardingStep1() -> NSView {
        let icon = NSTextField(labelWithString: "👋")
        icon.font = NSFont.systemFont(ofSize: 48)
        icon.alignment = .center

        let title = NSTextField(labelWithString: "Welcome to Nudge")
        title.font = NSFont.systemFont(ofSize: 24, weight: .heavy)
        title.textColor = .white
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Your floating productivity companion.\nLet's get you set up.")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping

        let nameLabel = NSTextField(labelWithString: "What should we call you?")
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.85)

        // Name input — styled container with an editable text field inside
        let nameBox = NSView()
        nameBox.wantsLayer = true
        nameBox.layer?.cornerRadius = 10
        nameBox.layer?.borderWidth = 1
        nameBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        nameBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        nameBox.translatesAutoresizingMaskIntoConstraints = false
        nameBox.heightAnchor.constraint(equalToConstant: 42).isActive = true

        // Plain NSTextField — works because the panel is a regular key window
        let nameField = NSTextField()
        nameField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        nameField.textColor = .white
        nameField.backgroundColor = .clear
        nameField.drawsBackground = false
        nameField.isBordered = false
        nameField.isBezeled = false
        nameField.focusRingType = .none
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.identifier = NSUserInterfaceItemIdentifier("onboard-name-field")
        nameField.placeholderAttributedString = NSAttributedString(
            string: "Your first name",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.35),
                .font: NSFont.systemFont(ofSize: 15, weight: .medium)
            ])

        nameBox.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: nameBox.leadingAnchor, constant: 14),
            nameField.trailingAnchor.constraint(equalTo: nameBox.trailingAnchor, constant: -14),
            nameField.centerYAnchor.constraint(equalTo: nameBox.centerYAnchor),
        ])

        let continueBtn = NSButton(title: "Continue", target: self, action: #selector(onboardingContinueTapped(_:)))
        continueBtn.bezelStyle = .inline
        continueBtn.isBordered = false
        continueBtn.wantsLayer = true
        continueBtn.layer?.cornerRadius = 10
        continueBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        continueBtn.attributedTitle = NSAttributedString(
            string: "  Continue  ",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ])
        continueBtn.translatesAutoresizingMaskIntoConstraints = false
        continueBtn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        continueBtn.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let topSpacer = NSView()
        let bottomSpacer = NSView()

        let stack = NSStackView(views: [
            topSpacer, icon, title, subtitle, nameLabel, nameBox, continueBtn, bottomSpacer
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(4, after: icon)
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(6, after: nameLabel)
        stack.setCustomSpacing(24, after: nameBox)

        nameBox.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        nameBox.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true

        return stack
    }

    @objc func onboardingContinueTapped(_ sender: Any?) {
        guard let blur = onboardingPanel?.contentView else { return }

        let nameId = NSUserInterfaceItemIdentifier("onboard-name-field")
        func findField(in view: NSView) -> NSTextField? {
            if let tf = view as? NSTextField, tf.identifier == nameId { return tf }
            for sub in view.subviews {
                if let found = findField(in: sub) { return found }
            }
            return nil
        }

        let name = findField(in: blur)?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if name.isEmpty {
            if let field = findField(in: blur), let box = field.superview {
                box.layer?.borderColor = NSColor.systemRed.cgColor
                box.layer?.borderWidth = 1.5
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    box.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
                    box.layer?.borderWidth = 1
                }
            }
            return
        }

        saveUserName(name)

        for sub in blur.subviews { sub.removeFromSuperview() }

        let step2 = buildOnboardingStep2()
        step2.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(step2)
        NSLayoutConstraint.activate([
            step2.topAnchor.constraint(equalTo: blur.topAnchor, constant: 32),
            step2.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 32),
            step2.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -32),
            step2.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - Step 2: Choose minimized view mode

    private static let scheduleCardId = NSUserInterfaceItemIdentifier("onboard-card-schedule")
    private static let todosCardId = NSUserInterfaceItemIdentifier("onboard-card-todos")
    private static let scheduleCheckId = NSUserInterfaceItemIdentifier("onboard-check-schedule")
    private static let todosCheckId = NSUserInterfaceItemIdentifier("onboard-check-todos")

    private func buildOnboardingStep2() -> NSView {
        let title = NSTextField(labelWithString: "Hey \(userName)! 🎉")
        title.font = NSFont.systemFont(ofSize: 22, weight: .heavy)
        title.textColor = .white
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Choose what you see on your floating widget.")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitle.alignment = .center

        let scheduleCard = makeOnboardingModeCard(
            emoji: "📅", modeName: "Schedule",
            description: "See your current block,\nnext up, and daily progress.",
            cardId: Self.scheduleCardId, checkId: Self.scheduleCheckId, selected: true)

        let todosCard = makeOnboardingModeCard(
            emoji: "✅", modeName: "Todos",
            description: "See your top tasks,\ncheck them off as you go.",
            cardId: Self.todosCardId, checkId: Self.todosCheckId, selected: false)

        let cardsRow = NSStackView(views: [scheduleCard, todosCard])
        cardsRow.orientation = .horizontal
        cardsRow.distribution = .fillEqually
        cardsRow.spacing = 14

        let startBtn = NSButton(title: "Get Started", target: self, action: #selector(onboardingFinishTapped(_:)))
        startBtn.bezelStyle = .inline
        startBtn.isBordered = false
        startBtn.wantsLayer = true
        startBtn.layer?.cornerRadius = 10
        startBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        startBtn.attributedTitle = NSAttributedString(
            string: "  Get Started  ",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ])
        startBtn.translatesAutoresizingMaskIntoConstraints = false
        startBtn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        startBtn.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let topSpacer = NSView()
        let bottomSpacer = NSView()

        let stack = NSStackView(views: [topSpacer, title, subtitle, cardsRow, startBtn, bottomSpacer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(24, after: subtitle)
        stack.setCustomSpacing(28, after: cardsRow)

        cardsRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        cardsRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true

        return stack
    }

    private func makeOnboardingModeCard(emoji: String, modeName: String, description: String, cardId: NSUserInterfaceItemIdentifier, checkId: NSUserInterfaceItemIdentifier, selected: Bool) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 2
        card.layer?.borderColor = selected
            ? NSColor.white.withAlphaComponent(0.8).cgColor
            : NSColor.white.withAlphaComponent(0.15).cgColor
        card.layer?.backgroundColor = selected
            ? NSColor.white.withAlphaComponent(0.1).cgColor
            : NSColor.white.withAlphaComponent(0.03).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.identifier = cardId

        let emojiLabel = NSTextField(labelWithString: emoji)
        emojiLabel.font = NSFont.systemFont(ofSize: 30)
        emojiLabel.alignment = .center

        let nameLabel = NSTextField(labelWithString: modeName)
        nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        descLabel.alignment = .center
        descLabel.maximumNumberOfLines = 3
        descLabel.lineBreakMode = .byWordWrapping

        let check = NSTextField(labelWithString: selected ? "●" : "○")
        check.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        check.textColor = selected ? .white : NSColor.white.withAlphaComponent(0.3)
        check.alignment = .center
        check.identifier = checkId

        let inner = NSStackView(views: [emojiLabel, nameLabel, descLabel, check])
        inner.orientation = .vertical
        inner.alignment = .centerX
        inner.spacing = 6
        inner.setCustomSpacing(2, after: emojiLabel)
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)

        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(onboardingCardTapped(_:)))
        card.addGestureRecognizer(click)

        return card
    }

    @objc func onboardingCardTapped(_ gesture: NSGestureRecognizer) {
        guard let card = gesture.view, let blur = onboardingPanel?.contentView else { return }
        let isSchedule = card.identifier == Self.scheduleCardId

        saveMinimizedViewMode(isSchedule ? "schedule" : "todos")

        func findView(id: NSUserInterfaceItemIdentifier, in view: NSView) -> NSView? {
            if view.identifier == id { return view }
            for sub in view.subviews {
                if let found = findView(id: id, in: sub) { return found }
            }
            return nil
        }

        let scheduleCard = findView(id: Self.scheduleCardId, in: blur)
        let todosCard = findView(id: Self.todosCardId, in: blur)

        scheduleCard?.layer?.borderColor = isSchedule
            ? NSColor.white.withAlphaComponent(0.8).cgColor
            : NSColor.white.withAlphaComponent(0.15).cgColor
        scheduleCard?.layer?.backgroundColor = isSchedule
            ? NSColor.white.withAlphaComponent(0.1).cgColor
            : NSColor.white.withAlphaComponent(0.03).cgColor

        todosCard?.layer?.borderColor = !isSchedule
            ? NSColor.white.withAlphaComponent(0.8).cgColor
            : NSColor.white.withAlphaComponent(0.15).cgColor
        todosCard?.layer?.backgroundColor = !isSchedule
            ? NSColor.white.withAlphaComponent(0.1).cgColor
            : NSColor.white.withAlphaComponent(0.03).cgColor

        if let schedCheck = findView(id: Self.scheduleCheckId, in: blur) as? NSTextField {
            schedCheck.stringValue = isSchedule ? "●" : "○"
            schedCheck.textColor = isSchedule ? .white : NSColor.white.withAlphaComponent(0.3)
        }
        if let todosCheck = findView(id: Self.todosCheckId, in: blur) as? NSTextField {
            todosCheck.stringValue = !isSchedule ? "●" : "○"
            todosCheck.textColor = !isSchedule ? .white : NSColor.white.withAlphaComponent(0.3)
        }
    }

    @objc func onboardingFinishTapped(_ sender: Any?) {
        // Move to Step 3: Accessibility permissions
        guard let blur = onboardingPanel?.contentView else { return }
        for sub in blur.subviews { sub.removeFromSuperview() }

        let step3 = buildOnboardingStep3()
        step3.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(step3)
        NSLayoutConstraint.activate([
            step3.topAnchor.constraint(equalTo: blur.topAnchor, constant: 32),
            step3.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 32),
            step3.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -32),
            step3.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -28),
        ])
    }

    // MARK: - Step 3: Accessibility permissions

    private func buildOnboardingStep3() -> NSView {
        let icon = NSTextField(labelWithString: "🔐")
        icon.font = NSFont.systemFont(ofSize: 48)
        icon.alignment = .center

        let title = NSTextField(labelWithString: "Accessibility Access")
        title.font = NSFont.systemFont(ofSize: 22, weight: .heavy)
        title.textColor = .white
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Nudge needs Accessibility access to detect\nglobal keyboard shortcuts (like ⌃⌥N to\nquick-add reminders) from any app.")
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 4
        subtitle.lineBreakMode = .byWordWrapping

        // Step-by-step instructions
        let steps = [
            "1.  Click \"Open Settings\" below — it opens\n     Privacy & Security → Accessibility.",
            "2.  Click the + button and add Nudge,\n     or toggle it on if it's already listed.",
            "3.  Come back here and click \"Done\".",
        ]

        let stepsStack = NSStackView()
        stepsStack.orientation = .vertical
        stepsStack.alignment = .leading
        stepsStack.spacing = 8

        for step in steps {
            let lbl = NSTextField(labelWithString: step)
            lbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            lbl.textColor = NSColor.white.withAlphaComponent(0.75)
            lbl.maximumNumberOfLines = 3
            lbl.lineBreakMode = .byWordWrapping
            lbl.preferredMaxLayoutWidth = 340
            stepsStack.addArrangedSubview(lbl)
        }

        // "Open Settings" button
        let openBtn = NSButton(title: "Open Settings", target: self, action: #selector(onboardingOpenAccessibility(_:)))
        openBtn.bezelStyle = .inline
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.cornerRadius = 10
        openBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        openBtn.attributedTitle = NSAttributedString(
            string: "  Open Settings  ",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ])
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        openBtn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        openBtn.widthAnchor.constraint(equalToConstant: 180).isActive = true

        // "Done" button
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(onboardingAccessibilityDone(_:)))
        doneBtn.bezelStyle = .inline
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 10
        doneBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        doneBtn.attributedTitle = NSAttributedString(
            string: "  Done  ",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
            ])
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.heightAnchor.constraint(equalToConstant: 36).isActive = true
        doneBtn.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let buttonsRow = NSStackView(views: [openBtn, doneBtn])
        buttonsRow.orientation = .horizontal
        buttonsRow.spacing = 12

        // Skip note
        let skipNote = NSTextField(labelWithString: "You can always enable this later in Nudge's Settings.")
        skipNote.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        skipNote.textColor = NSColor.white.withAlphaComponent(0.35)
        skipNote.alignment = .center

        let topSpacer = NSView()
        let bottomSpacer = NSView()

        let stack = NSStackView(views: [topSpacer, icon, title, subtitle, stepsStack, buttonsRow, skipNote, bottomSpacer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(4, after: icon)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(18, after: stepsStack)
        stack.setCustomSpacing(8, after: buttonsRow)

        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true

        return stack
    }

    @objc func onboardingOpenAccessibility(_ sender: Any?) {
        // Open System Settings → Privacy & Security → Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func onboardingAccessibilityDone(_ sender: Any?) {
        completeOnboarding()
        onboardingPanel?.orderOut(nil)
        onboardingPanel = nil

        // Launch the main HUD first, THEN demote the activation policy.
        finishLaunching()
        NSApp.setActivationPolicy(.prohibited)
    }
}
