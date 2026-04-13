//
//  Corner.swift
//  AnayHub
//
//  Which corner of the active screen the HUD panel is pinned to,
//  persisted across launches via UserDefaults.
//

import Foundation

enum Corner: String {
    case topLeft, topRight, bottomLeft, bottomRight

    static let storageKey = "AnayHub.corner"

    static var saved: Corner {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let c = Corner(rawValue: raw) { return c }
            return .topRight
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: storageKey) }
    }
}
