//
//  ProgressStats.swift
//  Nudge
//
//  Pure data computation for the Progress dashboard. Reads from the
//  caller-supplied done-state snapshot + ScheduleStore so the UI layer
//  doesn't need to do any math.
//

import Foundation

struct DayProgress {
    let dateKey: String       // "yyyy-MM-dd"
    let weekday: Int          // 1=Sun…7=Sat
    let doneCount: Int
    let totalCount: Int
    var percent: Int { totalCount == 0 ? 0 : Int(round(Double(doneCount) / Double(totalCount) * 100)) }
    var isStreakDay: Bool { percent >= ProgressStats.streakThresholdPercent }
}

struct ProgressStats {
    static let streakThresholdPercent = 70

    let today: DayProgress
    let thisWeek: [DayProgress]      // Mon..Sun ordered
    let currentStreak: Int
    let longestStreak: Int
    let allTimeDoneCount: Int
    let allTimeDaysTracked: Int
    let allTimeAveragePercent: Int
    /// Average completion % per weekday across all tracked history.
    /// Index 0 = Monday … 6 = Sunday. Nil if no data for that weekday.
    let perWeekdayAverages: [Int?]
    let bestWeekdayName: String?
    let bestWeekdayPercent: Int?
    let worstWeekdayName: String?
    let worstWeekdayPercent: Int?
    /// All-time personal records, for the records card.
    let mostDoneInOneDay: Int
    let mostDoneDate: String?
    let bestWeekPercent: Int
}

/// One pithy quote per day-of-year. Rotates so the dashboard never feels stale.
let MOTIVATIONAL_QUOTES: [String] = [
    "The secret of getting ahead is getting started. — Mark Twain",
    "Discipline equals freedom. — Jocko Willink",
    "We are what we repeatedly do. Excellence, then, is not an act, but a habit. — Aristotle",
    "Don't watch the clock; do what it does. Keep going. — Sam Levenson",
    "The best way out is always through. — Robert Frost",
    "It always seems impossible until it's done. — Nelson Mandela",
    "You don't have to be great to start, but you have to start to be great. — Zig Ziglar",
    "The expert in anything was once a beginner.",
    "Small daily improvements are the key to staggering long-term results.",
    "What you do every day matters more than what you do once in a while. — Gretchen Rubin",
    "Action is the foundational key to all success. — Pablo Picasso",
    "Motivation gets you going, but discipline keeps you growing. — John C. Maxwell",
    "Do something today that your future self will thank you for.",
    "Hard work beats talent when talent doesn't work hard. — Tim Notke",
    "The way to get started is to quit talking and begin doing. — Walt Disney",
    "Every accomplishment starts with the decision to try.",
    "Success is the sum of small efforts repeated day in and day out. — Robert Collier",
    "Don't count the days. Make the days count. — Muhammad Ali",
    "Focus on being productive instead of busy. — Tim Ferriss",
    "Your only limit is the amount of effort you're willing to put in.",
    "The man on top of the mountain didn't fall there. — Vince Lombardi",
    "Strive for progress, not perfection.",
    "Energy and persistence conquer all things. — Benjamin Franklin",
    "Wake up with determination. Go to bed with satisfaction.",
    "If you're going through hell, keep going. — Winston Churchill",
    "Don't limit your challenges. Challenge your limits.",
    "Either you run the day or the day runs you. — Jim Rohn",
    "Quality is not an act, it is a habit. — Aristotle",
    "Great things never came from comfort zones.",
    "Start where you are. Use what you have. Do what you can. — Arthur Ashe",
]

func quoteOfTheDay(for date: Date = Date()) -> String {
    let cal = Calendar.current
    let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
    return MOTIVATIONAL_QUOTES[day % MOTIVATIONAL_QUOTES.count]
}
