//
//  AppDelegate+Instructions.swift
//  AnayHub
//
//  A custom floating instructions panel — replaces the old NSAlert which
//  kept appearing behind other windows because AnayHub is a non-activating
//  agent app. This panel sits at statusWindow+2 level so it floats above
//  every other window, joins all spaces, and never steals focus from your
//  current app.
//

import Cocoa

@MainActor
extension AppDelegate {

    @objc func showInstructions(_ sender: Any?) {
        if instructionsPanel == nil {
            instructionsPanel = buildInstructionsPanel()
        }
        guard let panel = instructionsPanel else { return }
        // Always re-center on the active screen so it pops up where you're working.
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let f = panel.frame
        let x = v.midX - f.width / 2
        let y = v.midY - f.height / 2
        panel.setFrame(NSRect(x: x, y: y, width: f.width, height: f.height), display: false)
        panel.orderFrontRegardless()
    }

    @objc func dismissInstructions(_ sender: Any?) {
        instructionsPanel?.orderOut(nil)
    }

    private func buildInstructionsPanel() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: 480, height: 600)
        let panel = NSPanel(contentRect: rect,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Above the main HUD panel — instructions float over everything.
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Frosted background container
        let blur = NSVisualEffectView(frame: rect)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        // White hairline border
        let border = CALayer()
        border.frame = blur.bounds
        border.cornerRadius = 14
        border.borderWidth = 0.5
        border.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        blur.layer?.addSublayer(border)

        let content = buildInstructionsContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: blur.topAnchor, constant: 26),
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 26),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -26),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -22),
        ])

        panel.contentView = blur
        return panel
    }

    // MARK: - Content

    private func buildInstructionsContent() -> NSView {
        // Header
        let title = NSTextField(labelWithString: "How to use AnayHub")
        title.font = NSFont.systemFont(ofSize: 22, weight: .heavy)
        title.textColor = .white

        let subtitle = NSTextField(labelWithString: "Quick reference, Anay")
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.55)

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        // Sections — each one a (emoji, sectionTitle, [(key, description)])
        let sections: [(String, String, [(String, String)])] = [
            ("⌨", "KEYBOARD SHORTCUTS", [
                ("← → ↑ ↓", "Navigate the calendar picker"),
                ("Enter", "Pick the highlighted day"),
                ("Esc", "Close the calendar picker"),
                ("R⌘ + B", "Unhide panel (needs Accessibility, optional)"),
                ("R⌘ + D", "Mark current done (needs Accessibility, optional)"),
            ]),
            ("🛑", "QUITTING", [
                ("More tab", "Sidebar → More → Quit AnayHub"),
                ("Effect", "Stops AnayHub + prevents auto-restart"),
            ]),
            ("📌", "BASICS", [
                ("⤢", "Expand the panel (top-left of HUD)"),
                ("⤡", "Collapse back (top-right of expanded view)"),
                ("Drag", "Move the panel — snaps to nearest corner"),
                ("Auto-follow", "Follows your active app's screen"),
                ("ⓘ", "Open this guide any time"),
            ]),
            ("✓", "MARKING DONE", [
                ("Mark done", "Completes the current block"),
                ("Mark prev", "Retroactively complete the last block"),
                ("○ in Today", "Toggle any block from the timeline"),
                ("🔥 N", "Per-task streak — N consecutive days done"),
            ]),
            ("📝", "BLOCK NOTES", [
                ("✎ on a row", "Attach a one-line note to that block"),
                ("📝 marker", "Means a note is set; hover to preview"),
                ("Save / Clear", "Save updates, Clear removes the note"),
            ]),
            ("📅", "CALENDAR & SCHEDULE", [
                ("Schedule tab", "Mon-Sun strip + chevrons to change weeks"),
                ("📅 Pick Week", "Drill-down: year → month → day grid"),
                ("Today button", "Jump back to the current week"),
                ("Edit button", "Edit One-off (single date) or Permanent"),
                ("Editor rule", "Days must be gap-free 00:00 → 24:00"),
            ]),
            ("📊", "PROGRESS DASHBOARD", [
                ("Today ring", "Big % of today's blocks done"),
                ("Streaks", "Current 🔥 + best 🏆 (≥70% counts)"),
                ("20-20-20", "Live countdown to next eye break"),
                ("Day-of-week", "Best & worst days from history"),
                ("Records", "Most done in a day, best week"),
            ]),
            ("🙈", "HIDE FROM SCREEN", [
                ("Hide", "Removes the panel for up to 15 minutes"),
                ("Limit", "3 hides per day"),
                ("R⌘ + B", "Bring it back early"),
                ("On eye-break", "Auto-restores so you don't miss it"),
            ]),
            ("👀", "20-20-20 RULE", [
                ("Every 20 min", "Forced eye-break with bouncing message"),
                ("Soft chime", "On every break trigger + block change"),
                ("Snooze 2 min", "Up to 5 snoozes per break"),
                ("Done button", "Dismiss after looking ~20 sec away"),
            ]),
            ("💧", "WATER REMINDER", [
                ("Every hour", "Drink 250ml — half your bottle"),
                ("Every 2 hours", "Drink + go refill your bottle"),
                ("Notification", "Soft chime + system banner"),
                ("Pauses", "While the screen is asleep"),
            ]),
            ("⏳", "BLOCK FLOW", [
                ("Block change", "Notification + chime when a new block starts"),
                ("2 min warning", "Border pulses cyan + soft chime"),
                ("Time-of-day", "Block accent color shifts by part of day"),
            ]),
            ("✨", "DAILY & WEEKLY", [
                ("Intention prompt", "First expand of the day asks for 1 thing"),
                ("Today banner", "Your intention pinned at the top of Today"),
                ("Sunday 19:00", "End-of-week mood + one-line reflection"),
            ]),
            ("🌗", "AMBIENT & THEME", [
                ("Fullscreen", "Auto-shrinks to a tiny corner pill"),
                ("Light Mood", "More tab → toggle for a brighter HUD"),
            ]),
        ]

        let sectionStack = NSStackView()
        sectionStack.orientation = .vertical
        sectionStack.alignment = .leading
        sectionStack.spacing = 16
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        for (emoji, title, items) in sections {
            sectionStack.addArrangedSubview(makeInstructionsSection(emoji: emoji, title: title, items: items))
        }

        // Scrollable content (in case the user shrinks fonts or adds more)
        let scroll = makeScroll(content: sectionStack)
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Footer with close button
        let closeBtn = NSButton(title: "Got it", target: self, action: #selector(dismissInstructions(_:)))
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.wantsLayer = true
        closeBtn.layer?.cornerRadius = 7
        closeBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
        closeBtn.attributedTitle = NSAttributedString(
            string: "  Got it  ",
            attributes: [
                .foregroundColor: NSColor.black.withAlphaComponent(0.85),
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ])
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let footer = NSStackView(views: [NSView(), closeBtn])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let main = NSStackView(views: [header, scroll, footer])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 18
        main.translatesAutoresizingMaskIntoConstraints = false

        // Pin scroll + footer to full width of main
        scroll.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        scroll.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        footer.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        footer.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true

        return main
    }

    private func makeInstructionsSection(emoji: String, title: String, items: [(String, String)]) -> NSView {
        // Section header: "⌨  KEYBOARD SHORTCUTS"
        let head = NSTextField(labelWithString: "\(emoji)   \(title)")
        head.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        head.textColor = NSColor.systemBlue

        // Items list — key pill + description per row
        let itemsStack = NSStackView()
        itemsStack.orientation = .vertical
        itemsStack.alignment = .leading
        itemsStack.spacing = 6
        for (key, desc) in items {
            itemsStack.addArrangedSubview(makeInstructionsRow(key: key, description: desc))
        }

        let stack = NSStackView(views: [head, itemsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    private func makeInstructionsRow(key: String, description: String) -> NSView {
        // Pill-shaped key badge
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        keyLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        keyLabel.alignment = .center
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        let keyBg = NSView()
        keyBg.wantsLayer = true
        keyBg.layer?.cornerRadius = 5
        keyBg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        keyBg.layer?.borderWidth = 0.5
        keyBg.layer?.borderColor = NSColor.white.withAlphaComponent(0.20).cgColor
        keyBg.translatesAutoresizingMaskIntoConstraints = false
        keyBg.addSubview(keyLabel)
        NSLayoutConstraint.activate([
            keyLabel.leadingAnchor.constraint(equalTo: keyBg.leadingAnchor, constant: 7),
            keyLabel.trailingAnchor.constraint(equalTo: keyBg.trailingAnchor, constant: -7),
            keyLabel.centerYAnchor.constraint(equalTo: keyBg.centerYAnchor),
            keyBg.heightAnchor.constraint(equalToConstant: 20),
            keyBg.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])

        // Description
        let desc = NSTextField(labelWithString: description)
        desc.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        desc.textColor = NSColor.white.withAlphaComponent(0.85)
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 2

        let row = NSStackView(views: [keyBg, desc])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }
}
