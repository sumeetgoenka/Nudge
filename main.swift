//
//  main.swift
//  AnayHub — manual entry point (no @main, no storyboard)
//

import Cocoa

@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

MainActor.assumeIsolated {
    runApp()
}
