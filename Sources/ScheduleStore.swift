//
//  ScheduleStore.swift
//  Nudge
//
//  The single source of truth for Nudge's schedule data. Persists a
//  ScheduleDocument to ~/Library/Application Support/Nudge/schedule.json,
//  seeded on first launch from the hardcoded WEEKLY_RAW (with gap-fill applied
//  so the stored schedule is gap-free from day one).
//
//  Two layers:
//    - weeklyBase: the permanent weekly schedule keyed by Calendar weekday
//    - dateOverrides: per-date one-offs that take precedence on a single day
//
//  Validation rules enforced on every save:
//    - First block must start at 00:00
//    - Last block must end at 24:00
//    - Blocks must be sorted by start time
//    - No gaps and no overlaps between consecutive blocks
//    - Every block must have positive duration
//

import Foundation

/// One editable block. Times are stored as "HH:mm" strings, with the special
/// value "24:00" representing end-of-day (so the model never crosses midnight
/// ambiguously).
///
/// `compulsory` is optional for backwards-compat with old schedule.json
/// files written before this field existed. When nil, the effective value
/// falls back to a name-based default (Break / Sleep non-compulsory,
/// everything else compulsory).
struct EditableBlock: Codable, Equatable {
    var startStr: String
    var endStr: String
    var name: String
    var compulsory: Bool? = nil

    /// True if this block should be tickable / counted toward completion.
    /// Resolves the optional via the name-based default.
    var effectiveCompulsory: Bool {
        if let c = compulsory { return c }
        return EditableBlock.defaultCompulsory(forName: name)
    }

    /// Historical default — Break and Sleep are non-compulsory, every other
    /// named block is compulsory.
    static func defaultCompulsory(forName name: String) -> Bool {
        return name != "Break" && name != "Sleep"
    }
}

struct ScheduleDocument: Codable {
    /// "1" = Sunday … "7" = Saturday (Calendar.current weekday).
    var weeklyBase: [String: [EditableBlock]]
    /// "yyyy-MM-dd" → blocks. A specific date here overrides weeklyBase.
    var dateOverrides: [String: [EditableBlock]]
    /// Bumped whenever the hardcoded WEEKLY_RAW is updated. On launch, if
    /// the stored doc has a lower version, we re-seed `weeklyBase` from the
    /// new hardcoded data while preserving `dateOverrides` (so any one-off
    /// per-date edits the user made are kept). Optional for backwards-compat
    /// with docs written before this field existed (treated as version 0).
    var schemaVersion: Int? = nil
}

/// Bump this whenever WEEKLY_RAW changes so existing installs auto-migrate.
let CURRENT_SCHEDULE_SCHEMA_VERSION = 2

enum ScheduleValidationError: Error, CustomStringConvertible {
    case dayDoesNotStartAtMidnight
    case dayDoesNotEndAtMidnight
    case gap(afterName: String, afterEnd: String, beforeName: String, beforeStart: String)
    case overlap(firstName: String, secondName: String)
    case nonPositiveDuration(name: String)
    case invalidTime(value: String)
    case empty

    var description: String {
        switch self {
        case .dayDoesNotStartAtMidnight:
            return "Your day starts at 12:00 a.m. by default. You can add Sleep or a similar block at the beginning, or start your first block whenever you'd like."
        case .dayDoesNotEndAtMidnight:
            return "Your day ends at 12:00 a.m. by default. You can add a final block (e.g. Sleep) to close it out, or just leave it as-is."
        case .gap(let afterName, let afterEnd, let beforeName, let beforeStart):
            return "There's a gap between \"\(afterName)\" (ends \(afterEnd)) and \"\(beforeName)\" (starts \(beforeStart)). Fill it in or extend a block."
        case .overlap(let first, let second):
            return "\"\(first)\" and \"\(second)\" overlap. Adjust their times so they don't conflict."
        case .nonPositiveDuration(let name):
            return "\"\(name)\" ends before (or at) the same time it starts. Fix the times."
        case .invalidTime(let value):
            return "\"\(value)\" isn't a valid time. Use HH:mm (e.g. 08:30)."
        case .empty:
            return "A day can't be empty. Add at least one block (e.g., Sleep 00:00–24:00)."
        }
    }
}

@MainActor
final class ScheduleStore {
    static let shared = ScheduleStore()

    private(set) var document: ScheduleDocument
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Nudge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("schedule.json")

        if let data = try? Data(contentsOf: fileURL),
           var doc = try? JSONDecoder().decode(ScheduleDocument.self, from: data) {
            // Migration: if the stored schemaVersion is older than the
            // current hardcoded one, replace weeklyBase with the new seed
            // but PRESERVE the user's dateOverrides (one-off per-date edits).
            let storedVersion = doc.schemaVersion ?? 0
            if storedVersion < CURRENT_SCHEDULE_SCHEMA_VERSION {
                doc.weeklyBase = seedWeeklyBaseFromHardcoded()
                doc.schemaVersion = CURRENT_SCHEDULE_SCHEMA_VERSION
                self.document = doc
                try? persist()
            } else {
                self.document = doc
            }
        } else {
            // New user — start with an empty schedule (no hardcoded blocks).
            self.document = ScheduleDocument(
                weeklyBase: [:],
                dateOverrides: [:],
                schemaVersion: CURRENT_SCHEDULE_SCHEMA_VERSION)
            try? persist()
        }
    }

    // MARK: - Read

    func weeklyBase(for weekday: Int) -> [EditableBlock] {
        return document.weeklyBase[String(weekday)] ?? []
    }

    func dateOverride(for date: Date) -> [EditableBlock]? {
        return document.dateOverrides[Self.dateKey(date)]
    }

    func hasOverride(for date: Date) -> Bool {
        return dateOverride(for: date) != nil
    }

    // MARK: - Write (validated)

    /// Save a permanent edit to the weekly base for the given weekday.
    func saveWeeklyBase(_ blocks: [EditableBlock], for weekday: Int) throws {
        try Self.validate(blocks)
        document.weeklyBase[String(weekday)] = blocks
        try persist()
    }

    /// Save a one-off override for a specific calendar date.
    func saveDateOverride(_ blocks: [EditableBlock], for date: Date) throws {
        try Self.validate(blocks)
        document.dateOverrides[Self.dateKey(date)] = blocks
        try persist()
    }

    /// Remove a one-off override (revert that date back to the weekly base).
    func clearDateOverride(for date: Date) throws {
        document.dateOverrides.removeValue(forKey: Self.dateKey(date))
        try persist()
    }

    // MARK: - Persistence

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    static func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Validation

    /// Convert "HH:mm" (or the special "24:00") to minutes since midnight.
    /// Returns nil if the string isn't a valid time.
    static func minutes(of timeStr: String) -> Int? {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              h >= 0, m >= 0, m < 60 else { return nil }
        // Allow exactly 24:00 as end-of-day; otherwise hours 0..23.
        if h == 24 && m == 0 { return 24 * 60 }
        if h > 23 { return nil }
        return h * 60 + m
    }

    /// Throws ScheduleValidationError if the block list isn't a clean,
    /// gap-free 00:00–24:00 sequence with positive durations.
    static func validate(_ blocks: [EditableBlock]) throws {
        guard !blocks.isEmpty else { throw ScheduleValidationError.empty }

        // Parse all times up front so we can give a clean error per row.
        var parsed: [(start: Int, end: Int, name: String)] = []
        for b in blocks {
            guard let s = minutes(of: b.startStr) else {
                throw ScheduleValidationError.invalidTime(value: b.startStr)
            }
            guard let e = minutes(of: b.endStr) else {
                throw ScheduleValidationError.invalidTime(value: b.endStr)
            }
            if e <= s {
                throw ScheduleValidationError.nonPositiveDuration(name: b.name)
            }
            parsed.append((s, e, b.name))
        }

        // Sort by start so the user can enter rows in any order.
        parsed.sort { $0.start < $1.start }

        // No overlaps between consecutive blocks. Gaps are allowed.
        for i in 0..<(parsed.count - 1) {
            let cur = parsed[i]
            let nxt = parsed[i + 1]
            if cur.end > nxt.start {
                throw ScheduleValidationError.overlap(firstName: cur.name,
                                                      secondName: nxt.name)
            }
        }
    }

    static func formatMinutes(_ m: Int) -> String {
        let h = m / 60
        let mm = m % 60
        return String(format: "%02d:%02d", h, mm)
    }
}
