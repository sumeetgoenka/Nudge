//
//  AppDelegate+Expanded.swift
//  Nudge
//
//  Everything that builds the expanded (sidebar) view:
//    - expand/collapse animation
//    - sidebar with Today / Schedule / Week / To-Do sections
//    - per-section view builders (Today, Schedule, Week, To-Do)
//    - row factories (block row, schedule row, todo row, week row)
//

import Cocoa

@MainActor
extension AppDelegate {

    // MARK: - Expand / collapse

    @objc func toggleExpanded(_ sender: NSButton) {
        if isExpanded {
            collapsePanel()
        } else {
            expandPanel()
        }
    }

    func expandPanel() {
        guard !isExpanded else { return }
        isExpanded = true
        expandedSection = minimizedViewMode == "todos" ? .todo : .today
        minimizedFrame = panel.frame
        minimizedContentRoot?.isHidden = true
        contentView.isExpanded = true

        // Switch the panel into a standard titled/resizable app window with
        // Apple's traffic lights. We hijack the close + miniaturize buttons
        // so they collapse back to the floating HUD instead of closing.
        panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        panel.title = "Nudge"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.level = .normal
        panel.collectionBehavior = []
        panel.allowsKey = true
        if let close = panel.standardWindowButton(.closeButton) {
            close.target = self
            close.action = #selector(hideFromTitlebar(_:))
        }
        if let mini = panel.standardWindowButton(.miniaturizeButton) {
            mini.target = self
            mini.action = #selector(collapseFromTitlebar(_:))
        }

        // Lock the panel size BEFORE building content so autolayout can't
        // shrink the window when narrower sections are loaded.
        let target = Self.expandedFixedSize
        panel.contentMinSize = target
        panel.contentMaxSize = target
        let frame = frameForCorner(Corner.saved, size: target)
        panel.setFrame(frame, display: false)

        if expandedContentRoot == nil {
            buildExpandedRoot()
        }
        expandedContentRoot?.isHidden = false
        contentView.dragHandle = expandedDragStrip
        lastRenderedExpandedBlockIndex = currentBlockIndex
        rebuildExpandedMain()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Animate to the fixed expanded frame for visual smoothness.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    @objc func collapseFromTitlebar(_ sender: Any?) {
        collapsePanel()
    }

    @objc func hideFromTitlebar(_ sender: Any?) {
        collapsePanel()
        panel.orderOut(nil)
    }

    func collapsePanel() {
        guard isExpanded else { return }
        isExpanded = false
        contentView.isExpanded = false
        panel.allowsKey = false

        // Tear down expanded content entirely. Its internal min-width constraints
        // (sidebar + schedule day picker = ~438pt) would otherwise pin contentView
        // wide and prevent the panel from shrinking back to 196pt.
        expandedContentRoot?.removeFromSuperview()
        expandedContentRoot = nil
        expandedMainArea = nil
        expandedDragStrip = nil
        contentView.dragHandle = dragHandle
        expandedTaglineLabel = nil
        eyeBreakCountdownLabel = nil
        waterCountdownLabel = nil
        sidebarButtons.removeAll()
        scheduleDayButtons.removeAll()
        scheduleListContainer = nil
        todoInputField = nil
        todoDescField = nil

        // Restore the borderless floating HUD style.
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces,
                                    .fullScreenAuxiliary,
                                    .stationary,
                                    .ignoresCycle]

        // Unlock the panel size — minimized mode resizes itself.
        panel.contentMinSize = NSSize(width: 0, height: 0)
        panel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                      height: CGFloat.greatestFiniteMagnitude)

        // If the user changed widget mode while expanded, rebuild the
        // minimized view so it matches the new mode.
        let currentMode = minimizedViewMode
        let builtForSchedule = (minimizedMainStack?.arrangedSubviews.contains(where: { $0 === progressDotsRow }) == true)
        let needsRebuild = (currentMode == "schedule" && !builtForSchedule) ||
                           (currentMode == "todos" && builtForSchedule)
        if needsRebuild {
            minimizedContentRoot?.removeFromSuperview()
            minimizedContentRoot = nil
            minimizedMainStack = nil
            todosMiniContainer = nil
            if currentMode == "todos" {
                layoutTodosMinimized()
                updateTodosMiniList()
            } else {
                layoutScheduleMinimized()
            }
        }

        minimizedContentRoot?.isHidden = false

        let height = cachedMinimizedHeight > 0 ? cachedMinimizedHeight : 240
        let size = NSSize(width: panelWidth, height: height)
        let frame = frameForCorner(Corner.saved, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    func frameForCorner(_ corner: Corner, size: NSSize) -> NSRect {
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame
        let w = size.width, h = size.height
        switch corner {
        case .topLeft:     return NSRect(x: v.minX + edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .topRight:    return NSRect(x: v.maxX - w - edgeMargin, y: v.maxY - h - edgeMargin, width: w, height: h)
        case .bottomLeft:  return NSRect(x: v.minX + edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        case .bottomRight: return NSRect(x: v.maxX - w - edgeMargin, y: v.minY + edgeMargin, width: w, height: h)
        }
    }

    /// Fixed dimensions for the expanded panel — locked via contentMin/MaxSize
    /// while expanded so AppKit's autolayout pass can't resize it when content
    /// with a narrower intrinsic width is loaded.
    static let expandedFixedSize = NSSize(width: 580, height: 500)

    func expandedTargetSize() -> NSSize {
        return Self.expandedFixedSize
    }

    // MARK: - Expanded root (title bar + sidebar + main area)

    func buildExpandedRoot() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.bgTint.cgColor
        root.layer?.cornerRadius = 14
        contentView.addSubview(root)

        // Title bar — bigger wordmark + per-section tagline
        let wordmark = NSTextField(labelWithString: "Nudge")
        wordmark.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        wordmark.textColor = Theme.primary

        let tagline = NSTextField(labelWithString: taglineForSection(expandedSection))
        tagline.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        tagline.textColor = Theme.tertiary
        expandedTaglineLabel = tagline

        let titleStack = NSStackView(views: [wordmark, tagline])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0

        // Date label — sits between the wordmark and the chrome buttons.
        let dateF = DateFormatter()
        dateF.dateFormat = "EEE d MMM"
        let dateLabel = NSTextField(labelWithString: dateF.string(from: Date()))
        dateLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        dateLabel.textColor = Theme.secondary

        // Info button (ⓘ) — shows the instructions popup.
        let infoBtn = NSButton(title: "ⓘ", target: self, action: #selector(showInstructions(_:)))
        infoBtn.bezelStyle = .inline
        infoBtn.isBordered = false
        infoBtn.wantsLayer = true
        infoBtn.layer?.cornerRadius = 6
        infoBtn.layer?.backgroundColor = Theme.surface.cgColor
        infoBtn.attributedTitle = NSAttributedString(
            string: " ⓘ ",
            attributes: [
                .foregroundColor: Theme.secondary,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ])
        infoBtn.translatesAutoresizingMaskIntoConstraints = false
        infoBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        infoBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let collapseBtn = NSButton(title: "⤡", target: self, action: #selector(toggleExpanded(_:)))
        collapseBtn.bezelStyle = .inline
        collapseBtn.isBordered = false
        collapseBtn.wantsLayer = true
        collapseBtn.layer?.cornerRadius = 6
        collapseBtn.layer?.backgroundColor = Theme.surface.cgColor
        collapseBtn.attributedTitle = NSAttributedString(
            string: " ⤡ ",
            attributes: [
                .foregroundColor: Theme.secondary,
                .font: NSFont.systemFont(ofSize: 14, weight: .medium)
            ])
        collapseBtn.translatesAutoresizingMaskIntoConstraints = false
        collapseBtn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        collapseBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let titleRow = NSStackView(views: [titleStack, NSView(), dateLabel, infoBtn, collapseBtn])
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = buildSidebar()

        let main = NSView()
        main.translatesAutoresizingMaskIntoConstraints = false
        expandedMainArea = main

        let dragStrip = DragHandleView()
        dragStrip.translatesAutoresizingMaskIntoConstraints = false
        dragStrip.onDragEnded = { [weak self] in self?.snapToNearestCorner() }
        expandedDragStrip = dragStrip

        root.addSubview(dragStrip)
        root.addSubview(titleRow)
        root.addSubview(sidebar)
        root.addSubview(main)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            dragStrip.topAnchor.constraint(equalTo: root.topAnchor),
            dragStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            dragStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            dragStrip.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            titleRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            titleRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            titleRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            titleRow.heightAnchor.constraint(equalToConstant: 40),

            sidebar.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 16),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            sidebar.widthAnchor.constraint(equalToConstant: 144),

            main.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 16),
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 14),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            main.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        expandedContentRoot = root
    }

    func rebuildExpandedMain() {
        guard let main = expandedMainArea else { return }
        main.subviews.forEach { $0.removeFromSuperview() }
        // Drop refs to per-section live labels — they were owned by the
        // subtree we just removed and would be stale.
        eyeBreakCountdownLabel = nil
        waterCountdownLabel = nil
        let content: NSView
        switch expandedSection {
        case .today:    content = buildTodayView()
        case .schedule:
            content = isEditingSchedule ? buildScheduleEditorView() : buildScheduleView()
        case .week:     content = buildProgressView()
        case .todo:     content = buildTodoView()
        case .backlog:  content = buildBacklogView()
        case .more:     content = buildMoreView()
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        main.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: main.topAnchor),
            content.leadingAnchor.constraint(equalTo: main.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: main.bottomAnchor),
        ])

        // Sections with inline text fields need the panel to be key-capable.
        if expandedSection == .schedule || expandedSection == .todo {
            panel.allowsKey = true
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Sidebar

    func buildSidebar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        sidebarButtons.removeAll()
        let scheduleFirstItems: [(ExpandedSection, String, String)] = [
            (.today,    "Today",    "sun.max.fill"),
            (.schedule, "Schedule", "calendar"),
            (.week,     "Progress", "chart.bar.fill"),
            (.todo,     "To-Do",    "checklist"),
            (.backlog,  "Backlog",  "tray.full.fill"),
            (.more,     "More",     "ellipsis.circle.fill"),
        ]
        let todosFirstItems: [(ExpandedSection, String, String)] = [
            (.todo,     "To-Do",    "checklist"),
            (.today,    "Today",    "sun.max.fill"),
            (.schedule, "Schedule", "calendar"),
            (.week,     "Progress", "chart.bar.fill"),
            (.backlog,  "Backlog",  "tray.full.fill"),
            (.more,     "More",     "ellipsis.circle.fill"),
        ]
        let items = minimizedViewMode == "todos" ? todosFirstItems : scheduleFirstItems
        for (section, label, symbol) in items {
            let btn = SidebarItemButton(title: label, symbolName: symbol)
            btn.target = self
            btn.action = #selector(sidebarTapped(_:))
            btn.tag = sidebarTag(section)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 144).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            sidebarButtons[section] = btn
            stack.addArrangedSubview(btn)
        }
        styleSidebarButtons()
        return stack
    }

    func sidebarTag(_ s: ExpandedSection) -> Int {
        switch s {
        case .today: return 1
        case .schedule: return 2
        case .week: return 3
        case .todo: return 4
        case .backlog: return 5
        case .more: return 6
        }
    }
    func sectionForTag(_ t: Int) -> ExpandedSection {
        switch t {
        case 2: return .schedule
        case 3: return .week
        case 4: return .todo
        case 5: return .backlog
        case 6: return .more
        default: return .today
        }
    }

    @objc func sidebarTapped(_ sender: NSButton) {
        expandedSection = sectionForTag(sender.tag)
        styleSidebarButtons()
        expandedTaglineLabel?.stringValue = taglineForSection(expandedSection)
        rebuildExpandedMain()
        // Sections without inline text fields don't need key status.
        // The schedule editor's rebuildExpandedMain handles its own allowsKey.
        if expandedSection != .schedule {
            panel.allowsKey = false
        }
    }

    func taglineForSection(_ section: ExpandedSection) -> String {
        switch section {
        case .today:    return "Stay focused, \(userName) — one block at a time."
        case .schedule: return "Plan your week, \(userName). Own it."
        case .week:     return "Track your wins. Build the streak."
        case .todo:     return "Capture every loose thread, \(userName)."
        case .backlog:  return "Catch up on what slipped through, \(userName)."
        case .more:     return "Settings, controls, and the exit."
        }
    }

    /// Time-of-day greeting personalized with the user's name.
    func greetingForCurrentTime() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning, \(userName)."
        case 12..<17: return "Hey \(userName) — keep going."
        case 17..<21: return "Good evening, \(userName)."
        default:      return "Late night, \(userName)?"
        }
    }

    func styleSidebarButtons() {
        for (section, btn) in sidebarButtons {
            if let item = btn as? SidebarItemButton {
                item.isActive = (section == expandedSection)
            }
        }
    }

    // MARK: - Shared helpers

    func dayHeaderString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        return f.string(from: d)
    }

    func completionLine(for blocks: [ScheduleBlock]) -> String {
        let completable = blocks.filter { isCompletable($0) }
        let done = completable.filter { isDone($0) }.count
        return "\(done) of \(completable.count) tasks done"
    }

    /// Wrap content in a flipped container so scrolling starts at the top.
    func makeScroll(content: NSView) -> NSScrollView {
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: flipped.topAnchor),
            content.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
        ])

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = flipped
        NSLayoutConstraint.activate([
            flipped.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            flipped.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    // MARK: - Today view

    func buildTodayView() -> NSView {
        let header = NSTextField(labelWithString: greetingForCurrentTime())
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let stats = NSTextField(labelWithString: "\(dayHeaderString(Date())) · \(completionLine(for: todayBlocks))")
        stats.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        stats.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, stats])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 4
        list.translatesAutoresizingMaskIntoConstraints = false

        let hasRealBlocks = todayBlocks.contains { $0.name != "Sleep" && $0.name != "Break" }
        if !hasRealBlocks {
            let emptyIcon = NSTextField(labelWithString: "📭")
            emptyIcon.font = NSFont.systemFont(ofSize: 36)
            emptyIcon.alignment = .center
            emptyIcon.translatesAutoresizingMaskIntoConstraints = false
            let emptyMsg = NSTextField(labelWithString: "Nothing added for today.")
            emptyMsg.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            emptyMsg.textColor = Theme.tertiary
            emptyMsg.alignment = .center
            emptyMsg.translatesAutoresizingMaskIntoConstraints = false
            let emptyHint = NSTextField(labelWithString: "Head to Schedule to set up your day.")
            emptyHint.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyHint.textColor = Theme.muted
            emptyHint.alignment = .center
            emptyHint.translatesAutoresizingMaskIntoConstraints = false
            let emptyStack = NSStackView(views: [emptyIcon, emptyMsg, emptyHint])
            emptyStack.orientation = .vertical
            emptyStack.alignment = .centerX
            emptyStack.spacing = 6
            emptyStack.translatesAutoresizingMaskIntoConstraints = false
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: 40).isActive = true
            list.addArrangedSubview(spacer)
            list.addArrangedSubview(emptyStack)
            emptyStack.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
            emptyStack.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
        } else {
            for (i, block) in todayBlocks.enumerated() {
                let row = makeBlockRow(block, indexInToday: i)
                list.addArrangedSubview(row)
                row.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
                row.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
            }
        }

        let scroll = makeScroll(content: list)

        let stack = NSStackView(views: [headerStack, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        return stack
    }

    @objc func expandedToggleDone(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < todayBlocks.count else { return }
        let b = todayBlocks[i]
        guard isCompletable(b) else { return }
        setDone(b, !isDone(b))
        rebuildExpandedMain()
        updateBlockUI()
    }

    func makeBlockRow(_ block: ScheduleBlock, indexInToday: Int) -> NSView {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let isCur = (currentBlockIndex == indexInToday)
        let completable = isCompletable(block)
        let done = isDone(block)

        let row = BlockRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.highlighted = isCur
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true

        // Left accent bar — only visible for the current block.
        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.backgroundColor = isCur
            ? Theme.accent.cgColor
            : NSColor.clear.cgColor
        accent.layer?.cornerRadius = 1.5
        accent.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(accent)

        // Time column — fixed width, monospaced
        let timeStr = "\(f.string(from: block.start))–\(f.string(from: block.end))"
        let timeLabel = NSTextField(labelWithString: timeStr)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: isCur ? .semibold : .regular)
        timeLabel.textColor = completable
            ? (isCur ? Theme.primary : Theme.tertiary)
            : Theme.dim
        timeLabel.alignment = .left
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(timeLabel)

        // Status icon column — fixed width, button or filler.
        // Uses SF Symbols for a crisp checkmark / empty circle.
        let statusContainer = NSView()
        statusContainer.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(statusContainer)
        if completable {
            let btn = NSButton(title: "", target: self, action: #selector(expandedToggleDone(_:)))
            btn.bezelStyle = .inline
            btn.isBordered = false
            btn.tag = indexInToday
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.imagePosition = .imageOnly
            let symbolName = done ? "checkmark.circle.fill" : "circle"
            let config = NSImage.SymbolConfiguration(pointSize: 15,
                                                     weight: done ? .semibold : .regular)
            if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tint: NSColor = done
                    ? NSColor.systemGreen
                    : Theme.muted
                let tinted = img.copy() as! NSImage
                tinted.lockFocus()
                tint.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                btn.image = tinted
            }
            statusContainer.addSubview(btn)
            NSLayoutConstraint.activate([
                btn.centerXAnchor.constraint(equalTo: statusContainer.centerXAnchor),
                btn.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
                btn.widthAnchor.constraint(equalToConstant: 18),
                btn.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        // Name label — flexible. Append a 🔥N streak marker if the user has
        // completed this task name on N consecutive days (>= 2).
        var displayName = formatBlock(block)
        if completable {
            let streak = taskStreak(forName: block.name)
            if streak >= 2 {
                displayName += "  🔥\(streak)"
            }
        }
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: isCur ? .semibold : .regular)
        nameLabel.textColor = completable
            ? (isCur ? Theme.primary : Theme.secondary)
            : Theme.muted
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        if done {
            let attr = NSMutableAttributedString(string: formatBlock(block), attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: isCur ? .semibold : .regular),
                .foregroundColor: Theme.tertiary,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Theme.tertiary,
            ])
            nameLabel.attributedStringValue = attr
        }
        row.addSubview(nameLabel)

        // Note button — pencil if no note, filled note icon if one exists.
        // Click opens an inline editor popover.
        let hasNote = noteFor(block) != nil
        let noteBtn = NSButton(title: "", target: self,
                               action: #selector(blockNoteTapped(_:)))
        noteBtn.bezelStyle = .inline
        noteBtn.isBordered = false
        noteBtn.tag = indexInToday
        noteBtn.translatesAutoresizingMaskIntoConstraints = false
        noteBtn.attributedTitle = NSAttributedString(
            string: hasNote ? "📝" : "✎",
            attributes: [
                .foregroundColor: hasNote ? NSColor.systemYellow
                                          : Theme.muted,
                .font: NSFont.systemFont(ofSize: hasNote ? 13 : 14, weight: .regular)
            ])
        noteBtn.toolTip = noteFor(block) ?? "Add a note"
        row.addSubview(noteBtn)

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            accent.topAnchor.constraint(equalTo: row.topAnchor, constant: 6),
            accent.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
            accent.widthAnchor.constraint(equalToConstant: 3),

            timeLabel.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 10),
            timeLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 88),

            statusContainer.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 4),
            statusContainer.topAnchor.constraint(equalTo: row.topAnchor),
            statusContainer.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            statusContainer.widthAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: noteBtn.leadingAnchor, constant: -6),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            noteBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            noteBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            noteBtn.widthAnchor.constraint(equalToConstant: 20),
            noteBtn.heightAnchor.constraint(equalToConstant: 20),
        ])

        return row
    }

    @objc func blockNoteTapped(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < todayBlocks.count else { return }
        let block = todayBlocks[i]
        showBlockNoteEditor(for: block)
    }

    /// Tiny modal note editor — single text field, save / clear / cancel.
    func showBlockNoteEditor(for block: ScheduleBlock, on day: Date = Date()) {
        let alert = NSAlert()
        alert.messageText = "Note for \(formatBlock(block))"
        alert.informativeText = formatTimeRange(block)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        field.placeholderString = "One-line note (e.g. ch. 7 problems)"
        field.stringValue = noteFor(block, on: day) ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        // Float above the HUD.
        if let win = alert.window as? NSPanel {
            win.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 3)
        }
        // Allow text input.
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
        let resp = alert.runModal()
        panel.allowsKey = false

        switch resp {
        case .alertFirstButtonReturn:   // Save
            setNote(field.stringValue, for: block, on: day)
        case .alertSecondButtonReturn:  // Clear
            setNote("", for: block, on: day)
        default: break
        }
        rebuildExpandedMain()
    }

    // MARK: - Week view

    func buildWeekView() -> NSView {
        let header = NSTextField(labelWithString: "This Week")
        header.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        header.textColor = Theme.primary

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 8

        let cal = Calendar.current
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        for (i, wd) in weekdayOrder.enumerated() {
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            comps.weekday = wd
            let day = cal.date(from: comps) ?? Date()
            let blocks = todaysSchedule(for: day)
            let completable = blocks.filter { isCompletable($0) }
            let done = completable.filter { isDone($0, on: day) }.count
            let total = completable.count
            let frac = total > 0 ? CGFloat(done) / CGFloat(total) : 0
            list.addArrangedSubview(makeWeekRow(name: dayNames[i], done: done, total: total, frac: frac))
        }

        let stack = NSStackView(views: [header, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }

    func makeWeekRow(name: String, done: Int, total: Int, frac: CGFloat) -> NSView {
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = Theme.secondary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: 36).isActive = true

        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.surfaceHi.cgColor
        bar.layer?.cornerRadius = 3
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 220).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.backgroundColor = Theme.accent.cgColor
        fill.layer?.cornerRadius = 3
        fill.frame = NSRect(x: 0, y: 0, width: 220 * frac, height: 6)
        bar.addSubview(fill)

        let countLabel = NSTextField(labelWithString: "\(done)/\(total)")
        countLabel.font = NSFont.systemFont(ofSize: 11)
        countLabel.textColor = Theme.tertiary

        let row = NSStackView(views: [nameLabel, bar, countLabel])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        return row
    }

    // MARK: - To-Do view

    // ── Priority helpers ──

    private func todoPriorityColor(_ p: Int) -> NSColor {
        switch p {
        case 1: return NSColor(red: 1.00, green: 0.27, blue: 0.25, alpha: 1)
        case 2: return NSColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case 3: return Theme.accent
        default: return Theme.muted
        }
    }

    private func todoPriorityLabel(_ p: Int) -> String {
        switch p { case 1: return "P1"; case 2: return "P2"; case 3: return "P3"; default: return "P4" }
    }

    // ── Section grouping ──

    private enum TodoSection: String {
        case overdue = "Overdue", today = "Today", upcoming = "Upcoming", someday = "Someday"
    }

    private func groupedTodos() -> [(TodoSection, [AppDelegate.TodoItem])] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        var o: [AppDelegate.TodoItem] = [], t: [AppDelegate.TodoItem] = [],
            u: [AppDelegate.TodoItem] = [], s: [AppDelegate.TodoItem] = []
        for item in todos {
            guard let due = item.dueDate else { s.append(item); continue }
            let d = cal.startOfDay(for: due)
            if d < todayStart { o.append(item) } else if d == todayStart { t.append(item) } else { u.append(item) }
        }
        let cmp: (AppDelegate.TodoItem, AppDelegate.TodoItem) -> Bool = { a, b in
            a.priority != b.priority ? a.priority < b.priority : a.createdAt < b.createdAt
        }
        o.sort(by: cmp); t.sort(by: cmp); u.sort(by: cmp); s.sort(by: cmp)
        return [(.overdue, o), (.today, t), (.upcoming, u), (.someday, s)].filter { !$0.1.isEmpty }
    }

    // ── Due-date formatting ──

    private func formatDueDate(_ date: Date) -> (String, NSColor) {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        if days < -1  { return ("\(-days)d overdue", .systemRed) }
        if days == -1 { return ("Yesterday", .systemRed) }
        if days == 0  { return ("Today", .systemGreen) }
        if days == 1  { return ("Tomorrow", .systemOrange) }
        if days <= 7  { let f = DateFormatter(); f.dateFormat = "EEEE"; return (f.string(from: date), Theme.tertiary) }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return (f.string(from: date), Theme.muted)
    }

    // ── Subtitle + counters ──

    private func todoSubtitle() -> String {
        let done = todosCompletedTodayCount()
        if todos.isEmpty && done > 0 { return "\(done) done today \u{00b7} all clear!" }
        if todos.isEmpty { return "Nothing on your plate. Enjoy the calm." }
        let ov = todos.filter { guard let d = $0.dueDate else { return false }; return Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: Date()) }.count
        if ov > 0 { return "\(todos.count) task\(todos.count == 1 ? "" : "s") \u{00b7} \(ov) overdue" }
        if done > 0 { return "\(todos.count) left \u{00b7} \(done) done today" }
        return "\(todos.count) task\(todos.count == 1 ? "" : "s") \u{00b7} capture before they slip"
    }

    func todosCompletedTodayCount() -> Int {
        let today = todayKey(Date())
        guard UserDefaults.standard.string(forKey: "Nudge.todosCompletedDate") == today else { return 0 }
        return UserDefaults.standard.integer(forKey: "Nudge.todosCompletedCount")
    }

    func incrementTodosCompletedToday() {
        let today = todayKey(Date())
        if UserDefaults.standard.string(forKey: "Nudge.todosCompletedDate") != today {
            UserDefaults.standard.set(today, forKey: "Nudge.todosCompletedDate")
            UserDefaults.standard.set(1, forKey: "Nudge.todosCompletedCount")
        } else {
            UserDefaults.standard.set(todosCompletedTodayCount() + 1, forKey: "Nudge.todosCompletedCount")
        }
    }

    // ── Date-selection helpers ──

    private func isDateSelected(tag: Int) -> Bool {
        guard let sel = todoSelectedDueDate else { return false }
        let cal = Calendar.current; let td = cal.startOfDay(for: Date()); let sd = cal.startOfDay(for: sel)
        switch tag {
        case 10: return sd == td
        case 11: return sd == cal.date(byAdding: .day, value: 1, to: td)
        default: return false
        }
    }

    // ══════════════════════════════════════════════════════════════
    // MARK: Build To-Do view
    // ══════════════════════════════════════════════════════════════

    func buildTodoView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        // ── Header ──
        let title = NSTextField(labelWithString: "To-Do")
        title.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        title.textColor = Theme.primary
        title.translatesAutoresizingMaskIntoConstraints = false

        let sub = NSTextField(labelWithString: todoSubtitle())
        sub.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sub.textColor = Theme.tertiary
        sub.translatesAutoresizingMaskIntoConstraints = false

        let doneCount = todosCompletedTodayCount()
        let badge = NSTextField(labelWithString: doneCount > 0 ? "\u{2713} \(doneCount)" : "")
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badge.textColor = .systemGreen
        badge.translatesAutoresizingMaskIntoConstraints = false

        // ── Input box (Todoist-style: title + description in one card) ──
        let inputBox = NSView()
        inputBox.wantsLayer = true
        inputBox.layer?.cornerRadius = 10
        inputBox.layer?.borderWidth = 1
        inputBox.layer?.borderColor = Theme.border.cgColor
        inputBox.layer?.backgroundColor = Theme.surface.cgColor
        inputBox.translatesAutoresizingMaskIntoConstraints = false

        let input = ClickToFocusTextField()
        input.placeholderString = "Fix bike tire this weekend"
        input.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        input.textColor = Theme.primary
        input.bezelStyle = .roundedBezel
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.isEditable = true
        input.isSelectable = true
        input.target = self
        input.action = #selector(todoInputSubmitted(_:))
        input.translatesAutoresizingMaskIntoConstraints = false
        todoInputField = input

        let descInput = ClickToFocusTextField()
        descInput.placeholderString = "Description"
        descInput.font = NSFont.systemFont(ofSize: 11)
        descInput.textColor = Theme.secondary
        descInput.bezelStyle = .roundedBezel
        descInput.isBezeled = false
        descInput.drawsBackground = false
        descInput.focusRingType = .none
        descInput.isEditable = true
        descInput.isSelectable = true
        descInput.translatesAutoresizingMaskIntoConstraints = false
        todoDescField = descInput

        inputBox.addSubview(input)
        inputBox.addSubview(descInput)
        NSLayoutConstraint.activate([
            input.topAnchor.constraint(equalTo: inputBox.topAnchor, constant: 10),
            input.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 12),
            input.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -12),
            input.heightAnchor.constraint(equalToConstant: 20),
            descInput.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 2),
            descInput.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 12),
            descInput.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -12),
            descInput.heightAnchor.constraint(equalToConstant: 18),
            descInput.bottomAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: -10),
        ])

        // ── Action pills row (Date, Priority, Calendar) ──
        let optionsRow = NSStackView()
        optionsRow.orientation = .horizontal
        optionsRow.spacing = 6
        optionsRow.alignment = .centerY
        optionsRow.translatesAutoresizingMaskIntoConstraints = false

        // Date pills: Today / Tmrw
        for (label, iconName, tag) in [
            ("Today", "calendar", 10),
            ("Tmrw", "sun.max", 11),
        ] as [(String, String, Int)] {
            let pill = NSButton(title: "", target: self, action: #selector(todoDateTapped(_:)))
            pill.bezelStyle = .inline
            pill.isBordered = false
            pill.tag = tag
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 6
            pill.layer?.borderWidth = 1
            pill.translatesAutoresizingMaskIntoConstraints = false
            let sel = isDateSelected(tag: tag)
            pill.layer?.backgroundColor = sel
                ? Theme.accent.withAlphaComponent(0.15).cgColor
                : NSColor.clear.cgColor
            pill.layer?.borderColor = sel
                ? Theme.accent.withAlphaComponent(0.40).cgColor
                : Theme.border.cgColor
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
            let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            pill.image = img
            pill.imagePosition = .imageLeading
            pill.contentTintColor = sel ? Theme.accent : Theme.tertiary
            pill.attributedTitle = NSAttributedString(string: label,
                attributes: [
                    .foregroundColor: sel ? Theme.accent : Theme.tertiary,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                ])
            pill.heightAnchor.constraint(equalToConstant: 24).isActive = true
            optionsRow.addArrangedSubview(pill)
        }

        // Calendar picker pill — wider so it doesn't get squished
        let calBtn = NSButton(title: "", target: self, action: #selector(todoCalendarTapped(_:)))
        calBtn.bezelStyle = .inline
        calBtn.isBordered = false
        calBtn.wantsLayer = true
        calBtn.layer?.cornerRadius = 6
        calBtn.layer?.borderWidth = 1
        calBtn.translatesAutoresizingMaskIntoConstraints = false
        calBtn.toolTip = "Select date for the to-do"
        let hasCustomDate = todoSelectedDueDate != nil && !isDateSelected(tag: 10) && !isDateSelected(tag: 11)
        calBtn.layer?.backgroundColor = hasCustomDate
            ? Theme.accent.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
        calBtn.layer?.borderColor = hasCustomDate
            ? Theme.accent.withAlphaComponent(0.40).cgColor
            : Theme.border.cgColor
        let calIcon = NSImage(systemSymbolName: "calendar.badge.clock",
                              accessibilityDescription: "Pick date")
        let calConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        calBtn.image = calIcon?.withSymbolConfiguration(calConfig)
        calBtn.contentTintColor = hasCustomDate ? Theme.accent : Theme.tertiary
        if hasCustomDate, let d = todoSelectedDueDate {
            let (txt, _) = formatDueDate(d)
            calBtn.imagePosition = .imageLeading
            calBtn.attributedTitle = NSAttributedString(string: " \(txt) ",
                attributes: [
                    .foregroundColor: Theme.accent,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                ])
        } else {
            calBtn.imagePosition = .imageLeading
            calBtn.attributedTitle = NSAttributedString(string: " Date ",
                attributes: [
                    .foregroundColor: Theme.tertiary,
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                ])
        }
        calBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        optionsRow.addArrangedSubview(calBtn)

        // Priority dropdown pill — flag icon + "Priority" + chevron
        let prioBtn = NSButton(title: "", target: self, action: #selector(todoPriorityDropdownTapped(_:)))
        prioBtn.bezelStyle = .inline
        prioBtn.isBordered = false
        prioBtn.wantsLayer = true
        prioBtn.layer?.cornerRadius = 6
        prioBtn.layer?.borderWidth = 1
        prioBtn.translatesAutoresizingMaskIntoConstraints = false
        let pc = todoPriorityColor(todoSelectedPriority)
        let hasPrio = todoSelectedPriority < 4
        prioBtn.layer?.backgroundColor = hasPrio
            ? pc.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
        prioBtn.layer?.borderColor = hasPrio
            ? pc.withAlphaComponent(0.40).cgColor
            : Theme.border.cgColor
        let flagIcon = NSImage(systemSymbolName: hasPrio ? "flag.fill" : "flag",
                               accessibilityDescription: "Priority")
        let flagConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        prioBtn.image = flagIcon?.withSymbolConfiguration(flagConfig)
        prioBtn.imagePosition = .imageLeading
        prioBtn.contentTintColor = hasPrio ? pc : Theme.tertiary
        let prioLabel = hasPrio ? "Priority \(todoSelectedPriority)" : "Priority"
        prioBtn.attributedTitle = NSAttributedString(
            string: " \(prioLabel) \u{2304}",
            attributes: [
                .foregroundColor: hasPrio ? pc : Theme.tertiary,
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            ])
        prioBtn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        optionsRow.addArrangedSubview(prioBtn)

        // ── Bottom row: Cancel + Add task ──
        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        let cancelBtn = NSButton(title: "", target: self, action: #selector(todoCancelTapped(_:)))
        cancelBtn.bezelStyle = .inline
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 7
        cancelBtn.layer?.backgroundColor = Theme.surfaceHi.cgColor
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.attributedTitle = NSAttributedString(string: "  Cancel  ",
            attributes: [
                .foregroundColor: Theme.secondary,
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            ])
        cancelBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let addBtn = NSButton(title: "", target: self, action: #selector(todoAddBtnTapped(_:)))
        addBtn.bezelStyle = .inline
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 7
        addBtn.layer?.backgroundColor = Theme.accent.cgColor
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        addBtn.attributedTitle = NSAttributedString(string: "  Add task  ",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ])
        addBtn.heightAnchor.constraint(equalToConstant: 28).isActive = true

        bottomRow.addArrangedSubview(NSView()) // push to right
        bottomRow.addArrangedSubview(cancelBtn)
        bottomRow.addArrangedSubview(addBtn)

        root.addSubview(title)
        root.addSubview(sub)
        root.addSubview(badge)
        root.addSubview(inputBox)
        root.addSubview(optionsRow)
        root.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            badge.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            sub.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            inputBox.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 12),
            inputBox.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            inputBox.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            optionsRow.topAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: 8),
            optionsRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            optionsRow.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor),
            optionsRow.heightAnchor.constraint(equalToConstant: 26),
            bottomRow.topAnchor.constraint(equalTo: optionsRow.bottomAnchor, constant: 8),
            bottomRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottomRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottomRow.heightAnchor.constraint(equalToConstant: 30),
        ])

        // ── Task list ──
        let list = NSStackView()
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        if todos.isEmpty {
            let ev = buildTodoEmptyState()
            list.addArrangedSubview(ev); ev.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        } else {
            for (section, items) in groupedTodos() {
                let hdr = makeTodoSectionHeader(section, count: items.count)
                list.addArrangedSubview(hdr); hdr.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
                for item in items {
                    let row = makeTodoRow(item: item)
                    list.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
                }
            }
        }

        let scroll = makeScroll(content: list)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bottomRow.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        return root
    }

    // ── Section header ──

    private func makeTodoSectionHeader(_ section: TodoSection, count: Int) -> NSView {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let color: NSColor
        switch section {
        case .overdue: color = .systemRed; case .today: color = Theme.accent
        case .upcoming: color = Theme.tertiary
        case .someday: color = Theme.muted
        }
        let label = NSTextField(labelWithString: section.rawValue)
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold); label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        let cnt = NSTextField(labelWithString: "\(count)")
        cnt.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        cnt.textColor = color.withAlphaComponent(0.6); cnt.translatesAutoresizingMaskIntoConstraints = false
        let line = NSView(); line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true; line.layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        row.addSubview(label); row.addSubview(cnt); row.addSubview(line)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
            cnt.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
            cnt.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
        return row
    }

    // ── Task row (click text to edit) ──

    func makeTodoRow(item: AppDelegate.TodoItem) -> NSView {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false; row.wantsLayer = true

        // Priority circle
        let color = todoPriorityColor(item.priority)
        let check = NSButton(title: "", target: self, action: #selector(todoCheckTapped(_:)))
        check.bezelStyle = .inline; check.isBordered = false
        check.identifier = NSUserInterfaceItemIdentifier(item.id)
        check.translatesAutoresizingMaskIntoConstraints = false
        check.wantsLayer = true; check.layer?.cornerRadius = 9
        check.layer?.borderWidth = 1.5; check.layer?.borderColor = color.cgColor
        check.layer?.backgroundColor = NSColor.clear.cgColor
        check.attributedTitle = NSAttributedString(string: "")

        // Clickable title — opens edit modal
        let titleBtn = NSButton(title: item.text, target: self, action: #selector(todoRowTapped(_:)))
        titleBtn.bezelStyle = .inline; titleBtn.isBordered = false
        titleBtn.identifier = NSUserInterfaceItemIdentifier(item.id)
        titleBtn.alignment = .left
        titleBtn.translatesAutoresizingMaskIntoConstraints = false
        titleBtn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleBtn.attributedTitle = NSAttributedString(string: item.text,
            attributes: [.foregroundColor: Theme.secondary,
                         .font: NSFont.systemFont(ofSize: 12, weight: .regular)])

        // Description hint (if has description)
        var descLabel: NSTextField? = nil
        if !item.desc.isEmpty {
            let dl = NSTextField(labelWithString: item.desc)
            dl.font = NSFont.systemFont(ofSize: 10); dl.textColor = Theme.muted
            dl.lineBreakMode = .byTruncatingTail; dl.translatesAutoresizingMaskIntoConstraints = false
            dl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addSubview(dl); descLabel = dl
        }

        row.addSubview(check); row.addSubview(titleBtn)

        // Due date pill
        var duePill: NSTextField? = nil
        if let due = item.dueDate {
            let (txt, pc) = formatDueDate(due)
            let pill = NSTextField(labelWithString: txt)
            pill.font = NSFont.systemFont(ofSize: 9, weight: .semibold); pill.textColor = pc
            pill.wantsLayer = true; pill.layer?.cornerRadius = 4
            pill.layer?.backgroundColor = pc.withAlphaComponent(0.10).cgColor
            pill.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(pill); duePill = pill
        }

        var c: [NSLayoutConstraint] = [
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: item.desc.isEmpty ? 34 : 48),
            check.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            check.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            check.widthAnchor.constraint(equalToConstant: 18),
            check.heightAnchor.constraint(equalToConstant: 18),
            titleBtn.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
            titleBtn.topAnchor.constraint(equalTo: row.topAnchor, constant: 7),
        ]

        if let dl = descLabel {
            c += [
                dl.leadingAnchor.constraint(equalTo: titleBtn.leadingAnchor),
                dl.topAnchor.constraint(equalTo: titleBtn.bottomAnchor, constant: 1),
                dl.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6),
                dl.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -8),
            ]
        } else {
            c.append(titleBtn.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -7))
        }

        if let pill = duePill {
            c += [
                titleBtn.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -6),
                pill.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -4),
                pill.centerYAnchor.constraint(equalTo: check.centerYAnchor),
            ]
        } else {
            c.append(titleBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8))
        }
        NSLayoutConstraint.activate(c)
        return row
    }

    // ── Empty state ──

    private func buildTodoEmptyState() -> NSView {
        let box = NSView(); box.translatesAutoresizingMaskIntoConstraints = false
        let done = todosCompletedTodayCount()
        let icon = NSTextField(labelWithString: done > 0 ? "\u{2713}" : "\u{2610}")
        icon.font = NSFont.systemFont(ofSize: 36, weight: .ultraLight)
        icon.textColor = done > 0 ? .systemGreen : Theme.dim
        icon.alignment = .center; icon.translatesAutoresizingMaskIntoConstraints = false
        let msg = NSTextField(labelWithString: done > 0 ? "All clear, \(userName)." : "No tasks yet.")
        msg.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        msg.textColor = Theme.tertiary
        msg.alignment = .center; msg.translatesAutoresizingMaskIntoConstraints = false
        let detail = NSTextField(labelWithString: done > 0
            ? "You knocked out \(done) task\(done == 1 ? "" : "s") today. Enjoy the calm." : "Add one above to get started.")
        detail.font = NSFont.systemFont(ofSize: 11); detail.textColor = Theme.muted
        detail.alignment = .center; detail.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(icon); box.addSubview(msg); box.addSubview(detail)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            icon.centerXAnchor.constraint(equalTo: box.centerXAnchor), icon.topAnchor.constraint(equalTo: box.topAnchor, constant: 30),
            msg.centerXAnchor.constraint(equalTo: box.centerXAnchor), msg.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 8),
            detail.centerXAnchor.constraint(equalTo: box.centerXAnchor), detail.topAnchor.constraint(equalTo: msg.bottomAnchor, constant: 4),
        ])
        return box
    }

    // ══════════════════════════════════════════════════════════════
    // MARK: To-Do actions
    // ══════════════════════════════════════════════════════════════

    @objc func todoInputSubmitted(_ sender: NSTextField) { addTodoFromInput() }
    @objc func todoAddBtnTapped(_ sender: Any) { addTodoFromInput() }

    private func addTodoFromInput() {
        guard let field = todoInputField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let desc = todoDescField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var item = AppDelegate.TodoItem(text: text, priority: todoSelectedPriority, dueDate: todoSelectedDueDate)
        item.desc = desc
        todos.append(item)
        saveTodos()
        field.stringValue = ""
        todoDescField?.stringValue = ""
        todoSelectedPriority = 4
        todoSelectedDueDate = nil
        NSApp.setActivationPolicy(.accessory)
        rebuildExpandedMain()
    }

    @objc func todoCancelTapped(_ sender: Any?) {
        todoInputField?.stringValue = ""
        todoDescField?.stringValue = ""
        todoSelectedPriority = 4
        todoSelectedDueDate = nil
        NSApp.setActivationPolicy(.accessory)
        rebuildExpandedMain()
    }

    @objc func todoPriorityDropdownTapped(_ sender: NSButton) {
        let menu = NSMenu()
        for p in 1...4 {
            let item = NSMenuItem()
            let color = todoPriorityColor(p)
            let label = p < 4 ? "Priority \(p)" : "No priority"
            let check = (p == todoSelectedPriority) ? "  \u{2713}" : ""

            // Build an attributed title with the colored flag + label
            let str = NSMutableAttributedString()
            // Flag icon as text
            let flagName = p < 4 ? "flag.fill" : "flag"
            let flagConf = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            if let flagImg = NSImage(systemSymbolName: flagName, accessibilityDescription: nil)?
                .withSymbolConfiguration(flagConf) {
                let tinted = flagImg.copy() as! NSImage
                tinted.lockFocus()
                color.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                let attach = NSTextAttachment()
                attach.image = tinted
                str.append(NSAttributedString(attachment: attach))
                str.append(NSAttributedString(string: "  "))
            }
            str.append(NSAttributedString(string: "\(label)\(check)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: p == todoSelectedPriority ? .semibold : .regular),
                ]))
            item.attributedTitle = str
            item.tag = p
            item.target = self
            item.action = #selector(todoPriorityMenuPicked(_:))
            menu.addItem(item)
        }

        // Show menu below the button
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func todoPriorityMenuPicked(_ sender: NSMenuItem) {
        let t = todoInputField?.stringValue ?? ""
        let d = todoDescField?.stringValue ?? ""
        todoSelectedPriority = sender.tag
        rebuildExpandedMain()
        todoInputField?.stringValue = t
        todoDescField?.stringValue = d
    }

    @objc func todoCheckTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        todos.removeAll { $0.id == id }; saveTodos(); incrementTodosCompletedToday(); rebuildExpandedMain()
    }

    @objc func todoPriorityTapped(_ sender: NSButton) {
        let t = todoInputField?.stringValue ?? ""
        let d = todoDescField?.stringValue ?? ""
        todoSelectedPriority = sender.tag
        rebuildExpandedMain()
        todoInputField?.stringValue = t
        todoDescField?.stringValue = d
    }

    @objc func todoDateTapped(_ sender: NSButton) {
        let t = todoInputField?.stringValue ?? ""
        let d = todoDescField?.stringValue ?? ""
        let cal = Calendar.current; let td = cal.startOfDay(for: Date())
        let nd: Date? = sender.tag == 10 ? td : (sender.tag == 11 ? cal.date(byAdding: .day, value: 1, to: td) : nil)
        if let s = todoSelectedDueDate, let n = nd, cal.startOfDay(for: s) == cal.startOfDay(for: n) {
            todoSelectedDueDate = nil
        } else { todoSelectedDueDate = nd }
        rebuildExpandedMain()
        todoInputField?.stringValue = t
        todoDescField?.stringValue = d
    }

    // ── Edit existing todo (modal) ──

    @objc func todoRowTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let item = todos[idx]

        let alert = NSAlert()
        alert.messageText = "Edit task"
        alert.informativeText = ""

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 110))

        let titleLabel = NSTextField(labelWithString: "Title")
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = Theme.tertiary
        titleLabel.frame = NSRect(x: 0, y: 86, width: 300, height: 16)

        let titleField = NSTextField(frame: NSRect(x: 0, y: 60, width: 300, height: 24))
        titleField.stringValue = item.text
        titleField.font = NSFont.systemFont(ofSize: 13)

        let descLabel = NSTextField(labelWithString: "Description (optional)")
        descLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        descLabel.textColor = Theme.tertiary
        descLabel.frame = NSRect(x: 0, y: 38, width: 300, height: 16)

        let descField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 34))
        descField.stringValue = item.desc
        descField.placeholderString = "Add more detail\u{2026}"
        descField.font = NSFont.systemFont(ofSize: 12)

        container.addSubview(titleLabel)
        container.addSubview(titleField)
        container.addSubview(descLabel)
        container.addSubview(descField)
        alert.accessoryView = container

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.window.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 3)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(titleField)
        let resp = alert.runModal()
        NSApp.setActivationPolicy(.accessory)

        switch resp {
        case .alertFirstButtonReturn:
            let newText = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newText.isEmpty else { return }
            todos[idx].text = newText
            todos[idx].desc = descField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            saveTodos(); rebuildExpandedMain()
        case .alertSecondButtonReturn:
            todos.remove(at: idx); saveTodos(); rebuildExpandedMain()
        default: break
        }
    }

    // ══════════════════════════════════════════════════════════════
    // MARK: To-Do calendar picker (Sun–Sat, up to Jan 2028)
    // ══════════════════════════════════════════════════════════════

    @objc func todoCalendarTapped(_ sender: Any) {
        let savedText = todoInputField?.stringValue ?? ""
        todoCalPickerIsForNew = true
        todoCalEditingId = nil
        let cal = Calendar.current
        if let d = todoSelectedDueDate {
            todoCalPickerYear = cal.component(.year, from: d)
            todoCalPickerMonth = cal.component(.month, from: d)
        } else {
            todoCalPickerYear = cal.component(.year, from: Date())
            todoCalPickerMonth = cal.component(.month, from: Date())
        }
        showTodoCalendar()
        todoInputField?.stringValue = savedText
    }

    private func showTodoCalendar() {
        if todoCalendarPanel == nil { todoCalendarPanel = buildTodoCalendarPanel() }
        guard let p = todoCalendarPanel else { return }
        p.contentView = buildTodoCalendarContent()
        let screen = screenContainingActiveApp()
        let v = screen.visibleFrame; let f = p.frame
        p.setFrame(NSRect(x: v.midX - f.width / 2, y: v.midY - f.height / 2,
                          width: f.width, height: f.height), display: false)
        p.orderFrontRegardless()
    }

    private func buildTodoCalendarPanel() -> NSPanel {
        let rect = NSRect(x: 0, y: 0, width: 340, height: 380)
        let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.hasShadow = true; p.backgroundColor = .clear; p.isOpaque = false
        p.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }

    private func reloadTodoCalendar() {
        guard let p = todoCalendarPanel else { return }
        p.contentView = buildTodoCalendarContent()
    }

    @objc func dismissTodoCalendar(_ sender: Any?) {
        todoCalendarPanel?.orderOut(nil)
    }

    private func buildTodoCalendarContent() -> NSView {
        let rect = NSRect(x: 0, y: 0, width: 340, height: 380)
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

        // Header: < month year >  [Clear] [Close]
        let prevBtn = makePickerChromeButton(title: "\u{2039}", action: #selector(todoCalPrev(_:)))
        let nextBtn = makePickerChromeButton(title: "\u{203A}", action: #selector(todoCalNext(_:)))

        let titleStr = "\(monthName(todoCalPickerMonth)) \(todoCalPickerYear)"
        let titleLbl = NSTextField(labelWithString: titleStr)
        titleLbl.font = NSFont.systemFont(ofSize: 15, weight: .heavy)
        titleLbl.textColor = Theme.primary
        titleLbl.alignment = NSTextAlignment.center
        titleLbl.translatesAutoresizingMaskIntoConstraints = false

        let clearBtn = makePickerChromeButton(title: "Clear", action: #selector(todoCalClearDate(_:)))
        let closeBtn = makePickerChromeButton(title: "Close", action: #selector(dismissTodoCalendar(_:)))

        let headerRow = NSStackView(views: [prevBtn, titleLbl, nextBtn, NSView(), clearBtn, closeBtn])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6
        headerRow.translatesAutoresizingMaskIntoConstraints = false

        // Day-of-week header: Sun Mon Tue Wed Thu Fri Sat
        let dowRow = NSStackView()
        dowRow.orientation = .horizontal
        dowRow.distribution = .fillEqually
        dowRow.alignment = .centerY
        dowRow.spacing = 4
        dowRow.translatesAutoresizingMaskIntoConstraints = false
        for d in ["S", "M", "T", "W", "T", "F", "S"] {
            let lbl = NSTextField(labelWithString: d)
            lbl.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
            lbl.textColor = Theme.muted
            lbl.alignment = .center
            dowRow.addArrangedSubview(lbl)
        }

        // Day grid
        let grid = buildTodoCalDayGrid()
        grid.translatesAutoresizingMaskIntoConstraints = false

        let main = NSStackView(views: [headerRow, dowRow, grid])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 10
        main.translatesAutoresizingMaskIntoConstraints = false
        headerRow.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        headerRow.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        dowRow.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        dowRow.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        grid.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        grid.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true

        blur.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: blur.topAnchor, constant: 18),
            main.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 18),
            main.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -18),
            main.bottomAnchor.constraint(lessThanOrEqualTo: blur.bottomAnchor, constant: -14),
        ])
        return blur
    }

    private func buildTodoCalDayGrid() -> NSView {
        let cal = Calendar.current
        guard let first = cal.date(from: DateComponents(year: todoCalPickerYear, month: todoCalPickerMonth, day: 1)) else {
            return NSView()
        }
        let range = cal.range(of: .day, in: .month, for: first) ?? 1..<32
        // weekday: 1=Sun..7=Sat → Sun-first, so blanks = firstWeekday - 1
        let firstWD = cal.component(.weekday, from: first)
        let blanks = firstWD - 1

        let todayComps = cal.dateComponents([.year, .month, .day], from: Date())
        let selectedComps: DateComponents? = todoSelectedDueDate.map { cal.dateComponents([.year, .month, .day], from: $0) }

        // Limit: don't show months past Jan 2028
        let maxDate = cal.date(from: DateComponents(year: 2028, month: 1, day: 31))!

        let grid = makeGridStack(cols: 7)
        for _ in 0..<blanks { grid.addArrangedSubview(NSView()) }
        for d in 1...range.count {
            guard let date = cal.date(from: DateComponents(year: todoCalPickerYear, month: todoCalPickerMonth, day: d)) else { continue }
            let isToday = (d == todayComps.day && todoCalPickerMonth == todayComps.month! && todoCalPickerYear == todayComps.year!)
            let isSelected: Bool
            if let sc = selectedComps {
                isSelected = (d == sc.day && todoCalPickerMonth == sc.month! && todoCalPickerYear == sc.year!)
            } else { isSelected = false }
            let isPast = date > maxDate

            let cell = NSButton(title: "\(d)", target: self, action: #selector(todoCalDayTapped(_:)))
            cell.tag = d
            cell.isEnabled = !isPast
            styleDayGridCell(cell, day: d, isToday: isToday, isSelected: isSelected, isCursor: false)
            if isPast { cell.alphaValue = 0.3 }
            grid.addArrangedSubview(cell)
        }
        return grid
    }

    @objc func todoCalPrev(_ sender: Any?) {
        todoCalPickerMonth -= 1
        if todoCalPickerMonth < 1 { todoCalPickerMonth = 12; todoCalPickerYear -= 1 }
        reloadTodoCalendar()
    }

    @objc func todoCalNext(_ sender: Any?) {
        // Cap at Jan 2028
        if todoCalPickerYear == 2028 && todoCalPickerMonth >= 1 { return }
        todoCalPickerMonth += 1
        if todoCalPickerMonth > 12 { todoCalPickerMonth = 1; todoCalPickerYear += 1 }
        reloadTodoCalendar()
    }

    @objc func todoCalDayTapped(_ sender: NSButton) {
        let cal = Calendar.current
        guard let date = cal.date(from: DateComponents(year: todoCalPickerYear, month: todoCalPickerMonth, day: sender.tag)) else { return }
        todoSelectedDueDate = cal.startOfDay(for: date)
        dismissTodoCalendar(nil)
        rebuildExpandedMain()
    }

    @objc func todoCalClearDate(_ sender: Any?) {
        todoSelectedDueDate = nil
        dismissTodoCalendar(nil)
        rebuildExpandedMain()
    }
}
