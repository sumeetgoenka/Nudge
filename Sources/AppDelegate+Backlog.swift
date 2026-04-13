//
//  AppDelegate+Backlog.swift
//  Nudge
//
//  The Backlog sidebar view: lists every uncompleted, completable block from
//  past days. Each row has a "✓ Done" button (marks the item complete and
//  bumps the lifetime backlog-done counter shown on the Progress dashboard)
//  and a "Remove" button (silently drops the item without crediting it).
//

import Cocoa

@MainActor
extension AppDelegate {

    func buildBacklogView() -> NSView {
        let header = NSTextField(labelWithString: "Loose ends, \(userName).")
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let count = backlog.count
        let subtitle = NSTextField(labelWithString: count == 0
            ? "Nothing slipped through. Clean slate."
            : "\(count) item\(count == 1 ? "" : "s") to catch up on or let go.")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        // List of backlog rows, grouped by date for clarity.
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.translatesAutoresizingMaskIntoConstraints = false

        if backlog.isEmpty {
            let empty = NSTextField(labelWithString: "🎉 Woohoo — no backlog! Clean slate, \(userName).")
            empty.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            empty.textColor = Theme.secondary
            list.addArrangedSubview(empty)
        } else {
            // Group by dateKey to print a header per date.
            let grouped = Dictionary(grouping: backlog, by: { $0.dateKey })
            let sortedDates = grouped.keys.sorted(by: >)
            for dateKey in sortedDates {
                let dayHeader = makeBacklogDateHeader(dateKey)
                list.addArrangedSubview(dayHeader)
                dayHeader.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
                dayHeader.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
                for item in grouped[dateKey]! {
                    let row = makeBacklogRow(item)
                    list.addArrangedSubview(row)
                    row.leadingAnchor.constraint(equalTo: list.leadingAnchor).isActive = true
                    row.trailingAnchor.constraint(equalTo: list.trailingAnchor).isActive = true
                }
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

    private func makeBacklogDateHeader(_ dateKey: String) -> NSView {
        var displayDate = dateKey
        if let d = AppDelegate.parseDateKey(dateKey) {
            let f = DateFormatter()
            f.dateFormat = "EEEE, d MMM"
            displayDate = f.string(from: d)
        }
        let label = NSTextField(labelWithString: displayDate.uppercased())
        label.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        label.textColor = Theme.tertiary
        label.translatesAutoresizingMaskIntoConstraints = false

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeBacklogRow(_ item: BacklogItem) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 36).isActive = true
        row.wantsLayer = true
        row.layer?.cornerRadius = 8
        row.layer?.backgroundColor = Theme.surface.cgColor

        let timeLabel = NSTextField(labelWithString: "\(item.startStr)–\(item.endStr)")
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = Theme.tertiary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: item.name)
        nameLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = Theme.primary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let doneBtn = makeBacklogActionButton(title: "✓ Done",
                                              bg: NSColor.systemGreen.withAlphaComponent(0.85),
                                              fg: Theme.primary,
                                              action: #selector(backlogDoneTapped(_:)))
        let removeBtn = makeBacklogActionButton(title: "Remove",
                                                bg: Theme.surfaceHi,
                                                fg: Theme.secondary,
                                                action: #selector(backlogRemoveTapped(_:)))
        // Encode the item ID via tag — composite from index in backlog list.
        let idx = backlog.firstIndex(of: item) ?? -1
        doneBtn.tag = idx
        removeBtn.tag = idx

        row.addSubview(timeLabel)
        row.addSubview(nameLabel)
        row.addSubview(doneBtn)
        row.addSubview(removeBtn)
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            timeLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 88),

            nameLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneBtn.leadingAnchor, constant: -8),

            removeBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            removeBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            doneBtn.trailingAnchor.constraint(equalTo: removeBtn.leadingAnchor, constant: -8),
            doneBtn.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeBacklogActionButton(title: String, bg: NSColor, fg: NSColor, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = bg.cgColor
        btn.attributedTitle = NSAttributedString(
            string: "  \(title)  ",
            attributes: [
                .foregroundColor: fg,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ])
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return btn
    }

    @objc func backlogDoneTapped(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < backlog.count else { return }
        let item = backlog[i]
        backlogMarkDone(item)
        rebuildExpandedMain()
    }

    @objc func backlogRemoveTapped(_ sender: NSButton) {
        let i = sender.tag
        guard i >= 0 && i < backlog.count else { return }
        let item = backlog[i]
        backlogRemove(item)
        rebuildExpandedMain()
    }
}
