//
//  AppDelegate+Progress.swift
//  Nudge
//
//  Computes the ProgressStats snapshot from doneState + ScheduleStore, and
//  builds the Progress dashboard view (replaces the old "Week" section).
//

import Cocoa

@MainActor
extension AppDelegate {

    // MARK: - Stats computation

    /// Build a ProgressStats from current doneState + the schedule store.
    func computeProgressStats() -> ProgressStats {
        let cal = Calendar.current
        let now = Date()

        // ── Today
        let today = dayProgress(for: now)

        // ── This week (Mon..Sun in display order)
        var weekDays: [DayProgress] = []
        let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]  // Mon..Sun
        for wd in weekdayOrder {
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = wd
            if let d = cal.date(from: comps) {
                weekDays.append(dayProgress(for: d))
            }
        }

        // ── All-time + streaks + per-weekday + records
        let trackedDateKeys = Array(doneState.keys).sorted()
        var allTimeDoneCount = 0
        var allTimeTotalCount = 0
        // Per-weekday running totals (Mon..Sun = 0..6).
        var weekdayDoneTotals = Array(repeating: 0, count: 7)
        var weekdayBlockTotals = Array(repeating: 0, count: 7)
        // Personal records.
        var mostDoneInOneDay = 0
        var mostDoneDate: String? = nil
        var bestWeekPercentObserved = 0
        var weekKeyToDayProgresses: [String: [DayProgress]] = [:]

        for key in trackedDateKeys {
            guard let date = Self.parseDateKey(key) else { continue }
            let dp = dayProgress(for: date)
            allTimeDoneCount += dp.doneCount
            allTimeTotalCount += dp.totalCount

            // Mon-first weekday index 0..6
            let wd = cal.component(.weekday, from: date)
            let monIdx = (wd == 1) ? 6 : (wd - 2)
            weekdayDoneTotals[monIdx] += dp.doneCount
            weekdayBlockTotals[monIdx] += dp.totalCount

            // Most-done-in-one-day record
            if dp.doneCount > mostDoneInOneDay {
                mostDoneInOneDay = dp.doneCount
                mostDoneDate = key
            }

            // Group by ISO week-of-year for the best-week record
            let weekKey = "\(cal.component(.yearForWeekOfYear, from: date))-\(cal.component(.weekOfYear, from: date))"
            weekKeyToDayProgresses[weekKey, default: []].append(dp)
        }
        let avgPercent = allTimeTotalCount == 0 ? 0
            : Int(round(Double(allTimeDoneCount) / Double(allTimeTotalCount) * 100))

        // Best-week percent — average of the days in each tracked week.
        for (_, days) in weekKeyToDayProgresses {
            let totalDone = days.reduce(0) { $0 + $1.doneCount }
            let totalBlocks = days.reduce(0) { $0 + $1.totalCount }
            if totalBlocks > 0 {
                let pct = Int(round(Double(totalDone) / Double(totalBlocks) * 100))
                if pct > bestWeekPercentObserved { bestWeekPercentObserved = pct }
            }
        }

        // Per-weekday averages
        let perWeekdayAverages: [Int?] = (0..<7).map { i in
            let total = weekdayBlockTotals[i]
            if total == 0 { return nil }
            return Int(round(Double(weekdayDoneTotals[i]) / Double(total) * 100))
        }
        let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let validIdxs = (0..<7).compactMap { perWeekdayAverages[$0] != nil ? $0 : nil }
        let bestIdx = validIdxs.max { (perWeekdayAverages[$0] ?? 0) < (perWeekdayAverages[$1] ?? 0) }
        let worstIdx = validIdxs.min { (perWeekdayAverages[$0] ?? 0) < (perWeekdayAverages[$1] ?? 0) }

        let currentStreak = computeCurrentStreak(asOf: now)
        let longestStreak = computeLongestStreak()

        return ProgressStats(
            today: today,
            thisWeek: weekDays,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            allTimeDoneCount: allTimeDoneCount,
            allTimeDaysTracked: trackedDateKeys.count,
            allTimeAveragePercent: avgPercent,
            perWeekdayAverages: perWeekdayAverages,
            bestWeekdayName: bestIdx.map { weekdayNames[$0] },
            bestWeekdayPercent: bestIdx.flatMap { perWeekdayAverages[$0] },
            worstWeekdayName: worstIdx.map { weekdayNames[$0] },
            worstWeekdayPercent: worstIdx.flatMap { perWeekdayAverages[$0] },
            mostDoneInOneDay: mostDoneInOneDay,
            mostDoneDate: mostDoneDate,
            bestWeekPercent: bestWeekPercentObserved)
    }

    /// Computation helper — DayProgress for an arbitrary date.
    func dayProgress(for date: Date) -> DayProgress {
        let weekday = Calendar.current.component(.weekday, from: date)
        let key = todayKey(date)
        let blocks = todaysSchedule(for: date)
        let completable = blocks.filter { isCompletable($0) }
        let doneSet = doneState[key] ?? []
        let doneCount = completable.filter { doneSet.contains(blockKey($0)) }.count
        return DayProgress(dateKey: key, weekday: weekday,
                           doneCount: doneCount, totalCount: completable.count)
    }

    /// Walk backwards from `asOf`, counting consecutive days where the user
    /// hit ≥70% completion. The first non-streak day breaks the chain.
    /// If today itself isn't a streak day yet, we still check yesterday and
    /// before — so the streak doesn't temporarily zero out mid-day.
    private func computeCurrentStreak(asOf reference: Date) -> Int {
        let cal = Calendar.current
        var streak = 0
        var cursor = cal.startOfDay(for: reference)
        let todayProg = dayProgress(for: cursor)
        // If today already qualifies, count it.
        if todayProg.isStreakDay {
            streak += 1
        }
        // Walk backwards from yesterday until we hit a non-qualifying day.
        cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        while true {
            let dp = dayProgress(for: cursor)
            if dp.isStreakDay {
                streak += 1
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
            // Safety stop after 5 years to bound the walk.
            if streak > 365 * 5 { break }
        }
        return streak
    }

    /// Longest run of consecutive ≥70% days anywhere in the tracked history.
    /// Walks every date from the earliest tracked day to today.
    private func computeLongestStreak() -> Int {
        let cal = Calendar.current
        let trackedKeys = Array(doneState.keys).sorted()
        guard let firstKey = trackedKeys.first,
              let firstDate = Self.parseDateKey(firstKey) else { return 0 }

        var best = 0
        var run = 0
        var cursor = cal.startOfDay(for: firstDate)
        let endOfToday = cal.startOfDay(for: Date())
        while cursor <= endOfToday {
            let dp = dayProgress(for: cursor)
            if dp.isStreakDay {
                run += 1
                if run > best { best = run }
            } else {
                run = 0
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return best
    }

    static func parseDateKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    /// Per-task streak: how many consecutive days back from today (inclusive)
    /// had at least one DONE block with this exact name. Stops at the first
    /// gap. Returns 0 if today doesn't qualify.
    func taskStreak(forName name: String, asOf reference: Date = Date()) -> Int {
        let cal = Calendar.current
        var streak = 0
        var cursor = cal.startOfDay(for: reference)
        // Safety bound — 365 days back is enough.
        for _ in 0..<365 {
            let key = todayKey(cursor)
            let blocks = todaysSchedule(for: cursor).filter { $0.name == name && isCompletable($0) }
            let doneSet = doneState[key] ?? []
            let hitToday = blocks.contains { doneSet.contains(blockKey($0)) }
            if hitToday {
                streak += 1
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Dashboard view

    /// The Progress dashboard — replaces the old Week view in the sidebar.
    func buildProgressView() -> NSView {
        let stats = computeProgressStats()

        let header = NSTextField(labelWithString: "Look at you, \(userName).")
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let dateLabel = NSTextField(labelWithString: "\(dayHeaderString(Date())) · keep the streak alive")
        dateLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        dateLabel.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, dateLabel])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 1

        // Hero card — today's completion ring
        let hero = makeHeroCard(stats.today)

        // Streak row — current + best
        let streakRow = NSStackView(views: [
            makeStatCard(emoji: "🔥",
                         title: "STREAK",
                         value: "\(stats.currentStreak)",
                         suffix: stats.currentStreak == 1 ? "day" : "days",
                         tint: NSColor.systemOrange),
            makeStatCard(emoji: "🏆",
                         title: "BEST",
                         value: "\(stats.longestStreak)",
                         suffix: stats.longestStreak == 1 ? "day" : "days",
                         tint: NSColor.systemYellow),
        ])
        streakRow.orientation = .horizontal
        streakRow.spacing = 10
        streakRow.distribution = .fillEqually

        // 20-20-20 eye-break countdown (only if enabled)
        let eyeCard: NSView? = eyeBreakEnabled ? makeEyeBreakCard() : nil
        // Water reminder countdown (only if enabled)
        let waterCard: NSView? = waterRemindersEnabled ? makeWaterReminderCard() : nil

        // This week — bars
        let weekCard = makeWeekBarsCard(stats.thisWeek)

        // Day-of-week best / worst
        let dayOfWeekCard = makeDayOfWeekCard(stats)

        // Personal records
        let recordsCard = makeRecordsCard(stats)

        // All-time
        let allTimeCard = makeAllTimeCard(stats)

        // Quote
        let quote = NSTextField(labelWithString: quoteOfTheDay())
        quote.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        quote.textColor = Theme.tertiary
        quote.lineBreakMode = .byWordWrapping
        quote.maximumNumberOfLines = 3
        quote.preferredMaxLayoutWidth = 360
        quote.alignment = .center

        // Master scroll content
        var contentViews: [NSView] = [headerStack, hero, streakRow]
        if let eyeCard = eyeCard { contentViews.append(eyeCard) }
        if let waterCard = waterCard { contentViews.append(waterCard) }
        contentViews.append(contentsOf: [weekCard, dayOfWeekCard, recordsCard, allTimeCard, quote])

        let content = NSStackView(views: contentViews)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false

        var fullWidthViews: [NSView] = [hero, streakRow]
        if let eyeCard = eyeCard { fullWidthViews.append(eyeCard) }
        if let waterCard = waterCard { fullWidthViews.append(waterCard) }
        fullWidthViews.append(contentsOf: [weekCard, dayOfWeekCard, recordsCard, allTimeCard, quote])
        for v in fullWidthViews {
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        let scroll = makeScroll(content: content)

        var constraints: [NSLayoutConstraint] = []
        for v in fullWidthViews {
            constraints.append(v.leadingAnchor.constraint(equalTo: content.leadingAnchor))
            constraints.append(v.trailingAnchor.constraint(equalTo: content.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        return scroll
    }

    // MARK: - Card builders

    /// Generic rounded "card" container with a subtle background.
    private func makeCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = Theme.surface.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    /// The big "today" card with a circular ring + percent + count.
    private func makeHeroCard(_ today: DayProgress) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let title = NSTextField(labelWithString: "TODAY")
        title.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        title.textColor = Theme.tertiary
        title.translatesAutoresizingMaskIntoConstraints = false

        // Circular ring
        let ring = ProgressRingView(percent: CGFloat(today.percent) / 100.0)
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.widthAnchor.constraint(equalToConstant: 96).isActive = true
        ring.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let percentLabel = NSTextField(labelWithString: "\(today.percent)%")
        percentLabel.font = NSFont.systemFont(ofSize: 26, weight: .heavy)
        percentLabel.textColor = Theme.primary
        percentLabel.alignment = .left

        let countLabel = NSTextField(labelWithString: "\(today.doneCount) of \(today.totalCount) done")
        countLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = Theme.tertiary

        let textStack = NSStackView(views: [title, percentLabel, countLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setCustomSpacing(0, after: title)
        textStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(ring)
        card.addSubview(textStack)
        NSLayoutConstraint.activate([
            ring.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            ring.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: ring.trailingAnchor, constant: 16),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    /// Live water reminder countdown card. Counts down to the next 1-hour
    /// "drink 250ml" reminder. Updated by tick() once a second.
    private func makeWaterReminderCard() -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let emojiLabel = NSTextField(labelWithString: "💧")
        emojiLabel.font = NSFont.systemFont(ofSize: 22)

        let title = NSTextField(labelWithString: "WATER REMINDER")
        title.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        title.textColor = Theme.tertiary

        let countdown = NSTextField(labelWithString: formatWaterRemaining())
        countdown.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        countdown.textColor = Theme.accent
        waterCountdownLabel = countdown

        let suffix = NSTextField(labelWithString: "until your next 250ml")
        suffix.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        suffix.textColor = Theme.tertiary

        let valueRow = NSStackView(views: [countdown, suffix])
        valueRow.orientation = .horizontal
        valueRow.spacing = 6
        valueRow.alignment = .lastBaseline

        let textStack = NSStackView(views: [title, valueRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let row = NSStackView(views: [emojiLabel, textStack])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    /// Live 20-20-20 eye-break countdown card. The label is stored on
    /// AppDelegate.eyeBreakCountdownLabel and updated by tick() each second.
    private func makeEyeBreakCard() -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 70).isActive = true

        let emojiLabel = NSTextField(labelWithString: "👀")
        emojiLabel.font = NSFont.systemFont(ofSize: 22)

        let title = NSTextField(labelWithString: "20-20-20 RULE")
        title.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        title.textColor = Theme.tertiary

        let countdown = NSTextField(labelWithString: formatEyeBreakRemaining())
        countdown.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        countdown.textColor = NSColor.systemTeal
        eyeBreakCountdownLabel = countdown

        let suffix = NSTextField(labelWithString: "until you look out the window")
        suffix.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        suffix.textColor = Theme.tertiary

        let valueRow = NSStackView(views: [countdown, suffix])
        valueRow.orientation = .horizontal
        valueRow.spacing = 6
        valueRow.alignment = .lastBaseline

        let textStack = NSStackView(views: [title, valueRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let row = NSStackView(views: [emojiLabel, textStack])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    /// Compact stat card with an emoji + title + big value + suffix.
    private func makeStatCard(emoji: String, title: String, value: String, suffix: String, tint: NSColor) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 76).isActive = true

        let emojiLabel = NSTextField(labelWithString: emoji)
        emojiLabel.font = NSFont.systemFont(ofSize: 22, weight: .regular)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = Theme.tertiary

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 22, weight: .heavy)
        valueLabel.textColor = tint

        let suffixLabel = NSTextField(labelWithString: suffix)
        suffixLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        suffixLabel.textColor = Theme.tertiary

        let valueRow = NSStackView(views: [valueLabel, suffixLabel])
        valueRow.orientation = .horizontal
        valueRow.spacing = 4
        valueRow.alignment = .lastBaseline

        let textStack = NSStackView(views: [titleLabel, valueRow])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let row = NSStackView(views: [emojiLabel, textStack])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        return card
    }

    /// "This week" card with 7 vertical bars + day labels + small percent on top.
    private func makeWeekBarsCard(_ days: [DayProgress]) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let title = NSTextField(labelWithString: "THIS WEEK")
        title.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        title.textColor = Theme.tertiary
        title.translatesAutoresizingMaskIntoConstraints = false

        // Bars container
        let bars = NSStackView()
        bars.orientation = .horizontal
        bars.distribution = .fillEqually
        bars.alignment = .bottom
        bars.spacing = 6
        bars.translatesAutoresizingMaskIntoConstraints = false

        let dayShort = ["M", "T", "W", "T", "F", "S", "S"]
        let todayWd = Calendar.current.component(.weekday, from: Date())
        for (i, day) in days.enumerated() {
            let column = makeWeekColumn(label: dayShort[i],
                                        percent: day.percent,
                                        isToday: day.weekday == todayWd)
            bars.addArrangedSubview(column)
        }

        card.addSubview(title)
        card.addSubview(bars)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            bars.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            bars.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            bars.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            bars.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])
        return card
    }

    private func makeWeekColumn(label: String, percent: Int, isToday: Bool) -> NSView {
        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false

        let pctLabel = NSTextField(labelWithString: percent > 0 ? "\(percent)" : "")
        pctLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        pctLabel.textColor = Theme.tertiary
        pctLabel.alignment = .center
        pctLabel.translatesAutoresizingMaskIntoConstraints = false

        // Bar background (full height)
        let barBg = NSView()
        barBg.wantsLayer = true
        barBg.layer?.cornerRadius = 4
        barBg.layer?.backgroundColor = Theme.surface.cgColor
        barBg.translatesAutoresizingMaskIntoConstraints = false

        // Filled portion
        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.layer?.backgroundColor = isToday
            ? Theme.accent.cgColor
            : Theme.tertiary.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        barBg.addSubview(fill)

        let dayLabel = NSTextField(labelWithString: label)
        dayLabel.font = NSFont.systemFont(ofSize: 10, weight: isToday ? .semibold : .medium)
        dayLabel.textColor = isToday ? Theme.primary : Theme.tertiary
        dayLabel.alignment = .center
        dayLabel.translatesAutoresizingMaskIntoConstraints = false

        column.addSubview(pctLabel)
        column.addSubview(barBg)
        column.addSubview(dayLabel)

        let frac = max(0.04, CGFloat(percent) / 100.0)  // tiny stub even at 0%

        NSLayoutConstraint.activate([
            pctLabel.topAnchor.constraint(equalTo: column.topAnchor),
            pctLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            pctLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor),

            barBg.topAnchor.constraint(equalTo: pctLabel.bottomAnchor, constant: 2),
            barBg.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 4),
            barBg.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -4),
            barBg.bottomAnchor.constraint(equalTo: dayLabel.topAnchor, constant: -4),

            fill.leadingAnchor.constraint(equalTo: barBg.leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: barBg.trailingAnchor),
            fill.bottomAnchor.constraint(equalTo: barBg.bottomAnchor),
            fill.heightAnchor.constraint(equalTo: barBg.heightAnchor, multiplier: frac),

            dayLabel.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            dayLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            dayLabel.bottomAnchor.constraint(equalTo: column.bottomAnchor),
        ])
        return column
    }

    /// "Best / worst day-of-week" card.
    private func makeDayOfWeekCard(_ stats: ProgressStats) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let title = NSTextField(labelWithString: "DAY-OF-WEEK")
        title.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        title.textColor = Theme.tertiary
        title.translatesAutoresizingMaskIntoConstraints = false

        let bestText: String
        let worstText: String
        if let bn = stats.bestWeekdayName, let bp = stats.bestWeekdayPercent {
            bestText = "🌟 \(bn) · \(bp)%"
        } else {
            bestText = "🌟 — not enough data yet"
        }
        if let wn = stats.worstWeekdayName, let wp = stats.worstWeekdayPercent {
            worstText = "💤 \(wn) · \(wp)%"
        } else {
            worstText = "💤 — not enough data yet"
        }
        let best = NSTextField(labelWithString: bestText)
        best.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        best.textColor = NSColor.systemGreen
        let worst = NSTextField(labelWithString: worstText)
        worst.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        worst.textColor = NSColor.systemOrange

        let stack = NSStackView(views: [title, best, worst])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -10),
        ])
        return card
    }

    /// Personal records card — most done in one day, longest streak, best week.
    private func makeRecordsCard(_ stats: ProgressStats) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let title = NSTextField(labelWithString: "PERSONAL RECORDS")
        title.font = NSFont.systemFont(ofSize: 9, weight: .heavy)
        title.textColor = Theme.tertiary
        title.translatesAutoresizingMaskIntoConstraints = false

        let mostDate: String
        if let key = stats.mostDoneDate, let date = AppDelegate.parseDateKey(key) {
            let f = DateFormatter()
            f.dateFormat = "d MMM"
            mostDate = f.string(from: date)
        } else {
            mostDate = "—"
        }
        let mostLine = NSTextField(labelWithString: "🏅 Most done in a day · \(stats.mostDoneInOneDay) ✓ on \(mostDate)")
        let streakLine = NSTextField(labelWithString: "🔥 Longest streak · \(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")")
        let weekLine = NSTextField(labelWithString: "📈 Best week · \(stats.bestWeekPercent)%")
        let backlogLine = NSTextField(labelWithString: "🪃 Backlog rescued · \(backlogDoneCount) task\(backlogDoneCount == 1 ? "" : "s")")

        for lbl in [mostLine, streakLine, weekLine, backlogLine] {
            lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            lbl.textColor = Theme.secondary
            lbl.lineBreakMode = .byTruncatingTail
        }

        let stack = NSStackView(views: [title, mostLine, streakLine, weekLine, backlogLine])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.setCustomSpacing(6, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
        ])
        return card
    }

    /// "All-time" card — 3 stat cells side-by-side.
    private func makeAllTimeCard(_ stats: ProgressStats) -> NSView {
        let card = makeCard()
        card.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let title = NSTextField(labelWithString: "ALL-TIME")
        title.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        title.textColor = Theme.tertiary
        title.translatesAutoresizingMaskIntoConstraints = false

        let cell1 = makeAllTimeCell(value: "\(stats.allTimeDoneCount)", label: "tasks")
        let cell2 = makeAllTimeCell(value: "\(stats.allTimeDaysTracked)", label: "days")
        let cell3 = makeAllTimeCell(value: "\(stats.allTimeAveragePercent)%", label: "average")

        let row = NSStackView(views: [cell1, cell2, cell3])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(title)
        card.addSubview(row)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),

            row.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
        ])
        return card
    }

    private func makeAllTimeCell(value: String, label: String) -> NSView {
        let cell = NSView()
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = NSFont.systemFont(ofSize: 18, weight: .heavy)
        valueLabel.textColor = Theme.primary
        valueLabel.alignment = .left

        let labelLabel = NSTextField(labelWithString: label)
        labelLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        labelLabel.textColor = Theme.tertiary

        let stack = NSStackView(views: [valueLabel, labelLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            stack.topAnchor.constraint(equalTo: cell.topAnchor),
            stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
        ])
        return cell
    }
}
