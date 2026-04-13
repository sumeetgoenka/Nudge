//
//  Schedule.swift
//  Nudge
//
//  Weekly schedule data mirrored from the Nudge Next.js project
//  (src/app/schedule/page.tsx). Each raw entry has a start–end window and
//  an activity name. Gaps in the day are auto-filled at runtime: gaps
//  before 21:00 (and after 06:00) become "Break" blocks, anything after
//  21:00 or before 06:00 becomes "Sleep".
//

import Foundation

struct ScheduleBlock {
    let start: Date
    let end: Date
    let name: String
    let emoji: String?
    /// Tickable / counts toward completion. Computed from EditableBlock.
    let compulsory: Bool
}

private struct RawBlock {
    let startStr: String   // "H:mm" or "HH:mm"
    let endStr: String
    let name: String
}

// Calendar weekday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
private let WEEKLY_RAW: [Int: [RawBlock]] = [
    // Shared weekday morning (Mon–Fri)
    // 06:00 Brush & get ready → 06:20 Exercise → 06:50 Shower → 07:10 Catch up
    2: [ // Monday
        RawBlock(startStr: "6:00",  endStr: "6:20",  name: "Brush & get ready"),
        RawBlock(startStr: "6:20",  endStr: "6:50",  name: "Exercise"),
        RawBlock(startStr: "6:50",  endStr: "7:10",  name: "Shower"),
        RawBlock(startStr: "7:10",  endStr: "7:40",  name: "Morning catch-up"),
        RawBlock(startStr: "7:40",  endStr: "7:50",  name: "Tutor Time"),
        RawBlock(startStr: "7:50",  endStr: "9:10",  name: "Arabic B"),
        RawBlock(startStr: "9:10",  endStr: "10:30", name: "Science (school)"),
        RawBlock(startStr: "10:30", endStr: "10:50", name: "Tutor Time"),
        RawBlock(startStr: "10:50", endStr: "11:10", name: "Break"),
        RawBlock(startStr: "11:10", endStr: "12:30", name: "History (school)"),
        RawBlock(startStr: "12:30", endStr: "13:10", name: "Lunch"),
        RawBlock(startStr: "13:10", endStr: "13:50", name: "Academic Enrichment"),
        RawBlock(startStr: "13:50", endStr: "15:10", name: "Maths (school)"),
        RawBlock(startStr: "15:10", endStr: "16:00", name: "Maths (50)"),
        RawBlock(startStr: "16:00", endStr: "16:10", name: "Break"),
        RawBlock(startStr: "16:10", endStr: "17:00", name: "Biology (50)"),
        RawBlock(startStr: "17:00", endStr: "17:10", name: "Break"),
        RawBlock(startStr: "17:10", endStr: "18:00", name: "English (50)"),
        RawBlock(startStr: "18:00", endStr: "18:10", name: "Break"),
        RawBlock(startStr: "18:10", endStr: "19:00", name: "Keyboard (50)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    3: [ // Tuesday
        RawBlock(startStr: "6:00",  endStr: "6:20",  name: "Brush & get ready"),
        RawBlock(startStr: "6:20",  endStr: "6:50",  name: "Exercise"),
        RawBlock(startStr: "6:50",  endStr: "7:10",  name: "Shower"),
        RawBlock(startStr: "7:10",  endStr: "7:40",  name: "Morning catch-up"),
        RawBlock(startStr: "7:40",  endStr: "7:50",  name: "Tutor Time"),
        RawBlock(startStr: "7:50",  endStr: "9:10",  name: "Entrepreneurship"),
        RawBlock(startStr: "9:10",  endStr: "10:30", name: "Python / O'Reilly (school)"),
        RawBlock(startStr: "10:30", endStr: "10:50", name: "Tutor Time"),
        RawBlock(startStr: "10:50", endStr: "11:10", name: "Break"),
        RawBlock(startStr: "11:10", endStr: "12:30", name: "Empowering Global Citizens"),
        RawBlock(startStr: "12:30", endStr: "13:10", name: "Lunch"),
        RawBlock(startStr: "13:10", endStr: "13:50", name: "Moral Social Cultural"),
        RawBlock(startStr: "13:50", endStr: "15:10", name: "English (school)"),
        RawBlock(startStr: "15:10", endStr: "16:00", name: "Maths (50)"),
        RawBlock(startStr: "16:00", endStr: "16:10", name: "Break"),
        RawBlock(startStr: "16:10", endStr: "17:00", name: "Python (50)"),
        RawBlock(startStr: "17:00", endStr: "17:10", name: "Break"),
        RawBlock(startStr: "17:10", endStr: "18:00", name: "German (50)"),
        RawBlock(startStr: "18:00", endStr: "18:10", name: "Break"),
        RawBlock(startStr: "18:10", endStr: "19:00", name: "Guitar (50)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    4: [ // Wednesday
        RawBlock(startStr: "6:00",  endStr: "6:20",  name: "Brush & get ready"),
        RawBlock(startStr: "6:20",  endStr: "6:50",  name: "Exercise"),
        RawBlock(startStr: "6:50",  endStr: "7:10",  name: "Shower"),
        RawBlock(startStr: "7:10",  endStr: "7:40",  name: "Morning catch-up"),
        RawBlock(startStr: "7:40",  endStr: "7:50",  name: "Tutor Time"),
        RawBlock(startStr: "7:50",  endStr: "9:10",  name: "Arabic B"),
        RawBlock(startStr: "9:10",  endStr: "10:30", name: "Languages (school)"),
        RawBlock(startStr: "10:30", endStr: "10:50", name: "Tutor Time"),
        RawBlock(startStr: "10:50", endStr: "11:10", name: "Break"),
        RawBlock(startStr: "11:10", endStr: "12:30", name: "PE"),
        RawBlock(startStr: "12:30", endStr: "13:10", name: "Lunch"),
        RawBlock(startStr: "13:10", endStr: "13:50", name: "Maths (school)"),
        RawBlock(startStr: "13:50", endStr: "15:10", name: "English (school)"),
        RawBlock(startStr: "15:10", endStr: "16:00", name: "Maths (50)"),
        RawBlock(startStr: "16:00", endStr: "16:05", name: "Break"),
        RawBlock(startStr: "16:05", endStr: "16:55", name: "Chemistry (50)"),
        RawBlock(startStr: "16:55", endStr: "17:05", name: "Break"),
        RawBlock(startStr: "17:05", endStr: "17:55", name: "Python (50)"),
        RawBlock(startStr: "17:55", endStr: "18:05", name: "Break"),
        RawBlock(startStr: "18:05", endStr: "18:35", name: "Teach sister (30)"),
        RawBlock(startStr: "18:35", endStr: "18:40", name: "Break"),
        RawBlock(startStr: "18:40", endStr: "19:00", name: "Keyboard (20)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    5: [ // Thursday
        RawBlock(startStr: "6:00",  endStr: "6:20",  name: "Brush & get ready"),
        RawBlock(startStr: "6:20",  endStr: "6:50",  name: "Exercise"),
        RawBlock(startStr: "6:50",  endStr: "7:10",  name: "Shower"),
        RawBlock(startStr: "7:10",  endStr: "7:40",  name: "Morning catch-up"),
        RawBlock(startStr: "7:40",  endStr: "7:50",  name: "Tutor Time"),
        RawBlock(startStr: "7:50",  endStr: "9:10",  name: "Maths (school)"),
        RawBlock(startStr: "9:10",  endStr: "10:30", name: "English (school)"),
        RawBlock(startStr: "10:30", endStr: "10:50", name: "Tutor Time"),
        RawBlock(startStr: "10:50", endStr: "11:10", name: "Break"),
        RawBlock(startStr: "11:10", endStr: "12:30", name: "Entrepreneurship"),
        RawBlock(startStr: "12:30", endStr: "13:10", name: "Lunch"),
        RawBlock(startStr: "13:10", endStr: "13:50", name: "Languages (school)"),
        RawBlock(startStr: "13:50", endStr: "15:10", name: "Science (school)"),
        RawBlock(startStr: "15:10", endStr: "16:00", name: "Maths (50)"),
        RawBlock(startStr: "16:00", endStr: "16:10", name: "Break"),
        RawBlock(startStr: "16:10", endStr: "17:00", name: "English (50)"),
        RawBlock(startStr: "17:00", endStr: "17:10", name: "Break"),
        RawBlock(startStr: "17:10", endStr: "18:00", name: "German (50)"),
        RawBlock(startStr: "18:00", endStr: "18:05", name: "Break"),
        RawBlock(startStr: "18:05", endStr: "18:35", name: "Teach sister (30)"),
        RawBlock(startStr: "18:35", endStr: "18:40", name: "Break"),
        RawBlock(startStr: "18:40", endStr: "19:00", name: "Guitar (20)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    6: [ // Friday
        RawBlock(startStr: "6:00",  endStr: "6:20",  name: "Brush & get ready"),
        RawBlock(startStr: "6:20",  endStr: "6:50",  name: "Exercise"),
        RawBlock(startStr: "6:50",  endStr: "7:10",  name: "Shower"),
        RawBlock(startStr: "7:10",  endStr: "7:40",  name: "Morning catch-up"),
        RawBlock(startStr: "7:40",  endStr: "8:50",  name: "Languages (school)"),
        RawBlock(startStr: "8:50",  endStr: "10:00", name: "Geography (school)"),
        RawBlock(startStr: "10:00", endStr: "10:20", name: "Break"),
        RawBlock(startStr: "10:20", endStr: "11:30", name: "Science (school)"),
        RawBlock(startStr: "11:30", endStr: "12:00", name: "Personal catch-up"),
        RawBlock(startStr: "12:00", endStr: "12:50", name: "Maths (50)"),
        RawBlock(startStr: "12:50", endStr: "13:00", name: "Break"),
        RawBlock(startStr: "13:00", endStr: "13:50", name: "Physics (50)"),
        RawBlock(startStr: "13:50", endStr: "14:20", name: "Lunch"),
        RawBlock(startStr: "14:20", endStr: "15:10", name: "Python (50)"),
        RawBlock(startStr: "15:10", endStr: "15:20", name: "Break"),
        RawBlock(startStr: "15:20", endStr: "16:10", name: "Maths (50)"),
        RawBlock(startStr: "16:10", endStr: "16:20", name: "Break"),
        RawBlock(startStr: "16:20", endStr: "17:10", name: "English (50)"),
        RawBlock(startStr: "17:10", endStr: "17:20", name: "Break"),
        RawBlock(startStr: "17:20", endStr: "18:10", name: "Keyboard (50)"),
        RawBlock(startStr: "18:10", endStr: "18:20", name: "Break"),
        RawBlock(startStr: "18:20", endStr: "19:00", name: "Guitar (40)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    7: [ // Saturday
        RawBlock(startStr: "6:30",  endStr: "6:50",  name: "Brush & get ready"),
        RawBlock(startStr: "6:50",  endStr: "7:20",  name: "Exercise"),
        RawBlock(startStr: "7:20",  endStr: "7:40",  name: "Shower"),
        RawBlock(startStr: "7:40",  endStr: "8:30",  name: "Maths (50)"),
        RawBlock(startStr: "8:30",  endStr: "8:35",  name: "Break"),
        RawBlock(startStr: "8:35",  endStr: "9:10",  name: "Humanities (35)"),
        RawBlock(startStr: "9:10",  endStr: "10:00", name: "Breakfast"),
        RawBlock(startStr: "10:00", endStr: "10:50", name: "YouTube planning (50)"),
        RawBlock(startStr: "10:50", endStr: "11:00", name: "Break"),
        RawBlock(startStr: "11:00", endStr: "11:50", name: "Maths (50)"),
        RawBlock(startStr: "11:50", endStr: "12:00", name: "Break"),
        RawBlock(startStr: "12:00", endStr: "12:50", name: "Biology (50)"),
        RawBlock(startStr: "12:50", endStr: "13:00", name: "Buffer"),
        RawBlock(startStr: "13:00", endStr: "14:00", name: "Lunch"),
        RawBlock(startStr: "14:00", endStr: "14:50", name: "Maths (50)"),
        RawBlock(startStr: "14:50", endStr: "15:00", name: "Break"),
        RawBlock(startStr: "15:00", endStr: "15:30", name: "Teach sister (30)"),
        RawBlock(startStr: "15:30", endStr: "15:40", name: "Break"),
        RawBlock(startStr: "15:40", endStr: "16:30", name: "Physics (50)"),
        RawBlock(startStr: "16:30", endStr: "16:40", name: "Break"),
        RawBlock(startStr: "16:40", endStr: "17:30", name: "German (50)"),
        RawBlock(startStr: "17:30", endStr: "19:00", name: "🔒 Software dev — sacred 90min"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
    1: [ // Sunday
        RawBlock(startStr: "6:30",  endStr: "6:50",  name: "Brush & get ready"),
        RawBlock(startStr: "6:50",  endStr: "7:20",  name: "Exercise"),
        RawBlock(startStr: "7:20",  endStr: "7:40",  name: "Shower"),
        RawBlock(startStr: "7:40",  endStr: "9:10",  name: "YouTube filming (90)"),
        RawBlock(startStr: "9:10",  endStr: "10:00", name: "Breakfast"),
        RawBlock(startStr: "10:00", endStr: "10:50", name: "Maths (50)"),
        RawBlock(startStr: "10:50", endStr: "11:00", name: "Break"),
        RawBlock(startStr: "11:00", endStr: "11:50", name: "Keyboard (50)"),
        RawBlock(startStr: "11:50", endStr: "12:00", name: "Break"),
        RawBlock(startStr: "12:00", endStr: "12:40", name: "YouTube editing (40)"),
        RawBlock(startStr: "12:40", endStr: "13:00", name: "Buffer"),
        RawBlock(startStr: "13:00", endStr: "14:00", name: "Lunch"),
        RawBlock(startStr: "14:00", endStr: "14:50", name: "Maths (50)"),
        RawBlock(startStr: "14:50", endStr: "15:00", name: "Break"),
        RawBlock(startStr: "15:00", endStr: "15:30", name: "Teach sister (30)"),
        RawBlock(startStr: "15:30", endStr: "15:40", name: "Break"),
        RawBlock(startStr: "15:40", endStr: "16:30", name: "Chemistry (50)"),
        RawBlock(startStr: "16:30", endStr: "16:40", name: "Break"),
        RawBlock(startStr: "16:40", endStr: "17:30", name: "Python (50)"),
        RawBlock(startStr: "17:30", endStr: "17:40", name: "Break"),
        RawBlock(startStr: "17:40", endStr: "18:30", name: "Maths (50)"),
        RawBlock(startStr: "18:30", endStr: "18:40", name: "Break"),
        RawBlock(startStr: "18:40", endStr: "19:00", name: "English (20)"),
        RawBlock(startStr: "19:00", endStr: "20:00", name: "Dinner"),
        RawBlock(startStr: "20:00", endStr: "20:15", name: "English vocab"),
        RawBlock(startStr: "20:15", endStr: "20:30", name: "Wind down"),
        RawBlock(startStr: "20:30", endStr: "21:00", name: "Read"),
    ],
]

private func emojiFor(_ name: String) -> String? {
    // Strip trailing qualifiers like "(50)", "(school)", "(30)" so the
    // base lookup still hits — e.g. "Maths (50)" → "Maths".
    let stripped: String = {
        if let openParen = name.firstIndex(of: "("), name[name.index(before: openParen)] == " " {
            return String(name[..<name.index(before: openParen)])
        }
        return name
    }()
    switch stripped {
    case "Wake up & get ready": return "☀️"
    case "Brush & get ready":    return "🪥"
    case "Catch-up time":        return "✏️"
    case "Morning catch-up":     return "✏️"
    case "Personal catch-up":    return "✏️"
    case "School":               return "🏫"
    case "Tutor Time":           return "🪑"
    case "Arabic B":             return "🇸🇦"
    case "Academic Enrichment":  return "📚"
    case "Entrepreneurship":     return "💼"
    case "Empowering Global Citizens": return "🌐"
    case "Moral Social Cultural":      return "🕊"
    case "Languages":            return "🗣"
    case "PE":                   return "⚽"
    case "Eat + Exercise":       return "🍴"
    case "Maths":                return "📐"
    case "Break":                return "☕️"
    case "Keyboard":             return "🎹"
    case "Dinner":               return "🍽"
    case "English":              return "📖"
    case "English Vocab":        return "🔤"
    case "Computer Science":     return "💻"
    case "Biology":              return "🧬"
    case "Guitar":               return "🎸"
    case "History":              return "📜"
    case "Morning free time":   return "🌅"
    case "Lunch":                return "🥗"
    case "Chemistry":            return "⚗️"
    case "German":               return "🇩🇪"
    case "Geography":            return "🌍"
    case "Morning routine":      return "🪥"
    case "Exercise":             return "🏋️"
    case "Shower":               return "🚿"
    case "Breakfast":            return "🥞"
    case "Physics":              return "⚛️"
    case "Plan YouTube video":  return "🎬"
    case "YouTube planning":    return "🎬"
    case "YouTube editing":     return "✂️"
    case "YouTube filming":     return "🎥"
    case "Teach sister":         return "👩‍🏫"
    case "Read":                 return "📚"
    case "Science":              return "🔬"
    case "YouTube videos":       return "📹"
    case "Make YouTube video":   return "📹"
    case "Python":               return "🐍"
    case "Python / O'Reilly":    return "🐍"
    case "Humanities":           return "🏛"
    case "Wind down":            return "🧘"
    case "Buffer":               return "⏱"
    case "🔒 Software dev — sacred 90min": return "🔒"
    case "Sleep":                return "🌙"
    default:                     return nil
    }
}

private func parseTimeOnDay(_ s: String, day: Date) -> Date {
    let cal = Calendar.current
    let parts = s.split(separator: ":").compactMap { Int($0) }
    let hour = parts.count > 0 ? parts[0] : 0
    let minute = parts.count > 1 ? parts[1] : 0
    // Special case: "24:00" means start of next day (end-of-day marker).
    if hour == 24 && minute == 0 {
        let dayStart = cal.startOfDay(for: day)
        return cal.date(byAdding: .day, value: 1, to: dayStart) ?? day
    }
    var dc = cal.dateComponents([.year, .month, .day], from: day)
    dc.hour = hour
    dc.minute = minute
    dc.second = 0
    return cal.date(from: dc) ?? day
}

/// Build the full 24-hour block list for a given day from the ScheduleStore.
/// One-off date overrides take precedence over the weekly base.
@MainActor
func todaysSchedule(for day: Date = Date()) -> [ScheduleBlock] {
    let store = ScheduleStore.shared
    let cal = Calendar.current
    let weekday = cal.component(.weekday, from: day)

    let editable: [EditableBlock]
    if let override = store.dateOverride(for: day) {
        editable = override
    } else {
        editable = store.weeklyBase(for: weekday)
    }

    return editable.map { eb in
        ScheduleBlock(
            start: parseTimeOnDay(eb.startStr, day: day),
            end:   parseTimeOnDay(eb.endStr,   day: day),
            name:  eb.name,
            emoji: emojiFor(eb.name),
            compulsory: eb.effectiveCompulsory)
    }
}

/// Look up an emoji for a block name. Public so the editor can preview rows.
func emojiForName(_ name: String) -> String? {
    return emojiFor(name)
}

// MARK: - Seeding

/// Build the initial weeklyBase from the hardcoded WEEKLY_RAW, applying the
/// legacy gap-fill (Sleep before 06:00 / after 21:00, Break otherwise) so the
/// stored schedule is gap-free from the start. Used by ScheduleStore on its
/// first launch when no schedule.json exists yet.
func seedWeeklyBaseFromHardcoded() -> [String: [EditableBlock]] {
    var result: [String: [EditableBlock]] = [:]
    let cal = Calendar.current

    for weekday in 1...7 {
        // Pick a representative date with this weekday so parseTimeOnDay
        // can produce concrete times to compare against.
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = weekday
        let day = cal.date(from: comps) ?? Date()
        result[String(weekday)] = filledEditableBlocks(for: day)
    }
    return result
}

private func filledEditableBlocks(for day: Date) -> [EditableBlock] {
    let cal = Calendar.current
    let weekday = cal.component(.weekday, from: day)
    let raw = WEEKLY_RAW[weekday] ?? []

    let dayStart = cal.startOfDay(for: day)
    let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    let ninePM   = parseTimeOnDay("21:00", day: day)
    let sixAM    = parseTimeOnDay("6:00",  day: day)

    let dated: [(Date, Date, String)] = raw
        .map { (parseTimeOnDay($0.startStr, day: day),
                parseTimeOnDay($0.endStr,   day: day),
                $0.name) }
        .sorted { $0.0 < $1.0 }

    var result: [(Date, Date, String)] = []
    var cursor = dayStart

    func fillerName(from: Date) -> String {
        return (from < sixAM || from >= ninePM) ? "Sleep" : "Break"
    }

    for (s, e, n) in dated {
        if s > cursor {
            result.append((cursor, s, fillerName(from: cursor)))
        }
        result.append((s, e, n))
        cursor = max(cursor, e)
    }
    if cursor < dayEnd {
        result.append((cursor, dayEnd, fillerName(from: cursor)))
    }

    // Convert to EditableBlock with "HH:mm" strings (and "24:00" for end-of-day).
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return result.map { (s, e, n) in
        let endStr: String
        if e == dayEnd {
            endStr = "24:00"
        } else {
            endStr = f.string(from: e)
        }
        return EditableBlock(startStr: f.string(from: s), endStr: endStr, name: n)
    }
}
