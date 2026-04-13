//
//  AppDelegate+More.swift
//  AnayHub
//
//  The "More" sidebar tab — currently houses the Complete Quit button.
//  Future home for settings (sounds, notification toggles, theme, etc.).
//

import Cocoa

@MainActor
extension AppDelegate {

    func buildMoreView() -> NSView {
        let header = NSTextField(labelWithString: "More")
        header.font = NSFont.systemFont(ofSize: 20, weight: .heavy)
        header.textColor = Theme.primary

        let subtitle = NSTextField(labelWithString: "Controls and the exit")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = Theme.tertiary

        let headerStack = NSStackView(views: [header, subtitle])
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 2

        // ── Quit card ────────────────────────────────────────────────
        let quitCard = makeMoreCard()
        quitCard.heightAnchor.constraint(equalToConstant: 130).isActive = true

        let quitTitle = NSTextField(labelWithString: "Completely quit AnayHub")
        quitTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        quitTitle.textColor = Theme.primary

        let quitBlurb = NSTextField(labelWithString: "Stops AnayHub and unloads it from launchd so it won't auto-restart at next login. You can launch it again from the .app whenever you like.")
        quitBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        quitBlurb.textColor = Theme.tertiary
        quitBlurb.lineBreakMode = .byWordWrapping
        quitBlurb.maximumNumberOfLines = 3
        quitBlurb.preferredMaxLayoutWidth = 380

        let quitBtn = NSButton(title: "Quit AnayHub", target: self,
                               action: #selector(moreQuitTapped(_:)))
        quitBtn.bezelStyle = .inline
        quitBtn.isBordered = false
        quitBtn.wantsLayer = true
        quitBtn.layer?.cornerRadius = 7
        quitBtn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        quitBtn.attributedTitle = NSAttributedString(
            string: "  Quit AnayHub  ",
            attributes: [
                .foregroundColor: Theme.primary,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ])
        quitBtn.translatesAutoresizingMaskIntoConstraints = false
        quitBtn.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let cardStack = NSStackView(views: [quitTitle, quitBlurb, quitBtn])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 8
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        quitCard.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: quitCard.topAnchor, constant: 14),
            cardStack.leadingAnchor.constraint(equalTo: quitCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: quitCard.trailingAnchor, constant: -16),
            cardStack.bottomAnchor.constraint(lessThanOrEqualTo: quitCard.bottomAnchor, constant: -14),
        ])

        // ── Light-mood toggle card ──────────────────────────────────
        let moodCard = makeMoreCard()
        moodCard.heightAnchor.constraint(equalToConstant: 100).isActive = true

        let moodTitle = NSTextField(labelWithString: "Light Mood")
        moodTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        moodTitle.textColor = Theme.primary

        let moodBlurb = NSTextField(labelWithString: "Switches the HUD to a softer, less moody frosted background. Easier on the eyes for long sessions.")
        moodBlurb.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        moodBlurb.textColor = Theme.tertiary
        moodBlurb.lineBreakMode = .byWordWrapping
        moodBlurb.maximumNumberOfLines = 2
        moodBlurb.preferredMaxLayoutWidth = 380

        let moodToggle = NSButton(checkboxWithTitle: "  Enable Light Mood",
                                  target: self,
                                  action: #selector(lightMoodToggled(_:)))
        moodToggle.state = lightMoodEnabled ? .on : .off
        moodToggle.contentTintColor = Theme.primary
        moodToggle.translatesAutoresizingMaskIntoConstraints = false

        let moodStack = NSStackView(views: [moodTitle, moodBlurb, moodToggle])
        moodStack.orientation = .vertical
        moodStack.alignment = .leading
        moodStack.spacing = 6
        moodStack.translatesAutoresizingMaskIntoConstraints = false
        moodCard.addSubview(moodStack)
        NSLayoutConstraint.activate([
            moodStack.topAnchor.constraint(equalTo: moodCard.topAnchor, constant: 14),
            moodStack.leadingAnchor.constraint(equalTo: moodCard.leadingAnchor, constant: 16),
            moodStack.trailingAnchor.constraint(equalTo: moodCard.trailingAnchor, constant: -16),
            moodStack.bottomAnchor.constraint(lessThanOrEqualTo: moodCard.bottomAnchor, constant: -10),
        ])

        // ── Master stack ─────────────────────────────────────────────
        let main = NSStackView(views: [headerStack, moodCard, quitCard])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 16
        main.translatesAutoresizingMaskIntoConstraints = false
        moodCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        moodCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        quitCard.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
        quitCard.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        return main
    }

    @objc func lightMoodToggled(_ sender: NSButton) {
        lightMoodEnabled = (sender.state == .on)
        applyLightMoodTheme()
    }

    private func makeMoreCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = Theme.surface.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    @objc func moreQuitTapped(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Quit AnayHub completely?"
        alert.informativeText = "AnayHub will stop and won't auto-restart at next login. You can launch it again from the .app whenever you like."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        // Make the alert appear in front of the floating panel.
        if let alertWindow = alert.window as? NSPanel {
            alertWindow.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 3)
        }
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            performCompleteQuit()
        }
    }

    /// Tear-down sequence for a clean quit:
    ///   1. unload the launchd agent (so it doesn't restart us)
    ///   2. delete the launchd plist file (so launchd doesn't reload it at login)
    ///   3. terminate the app
    func performCompleteQuit() {
        unloadLaunchdAgentPublic()
        deleteLaunchdAgentFile()
        NSApp.terminate(nil)
    }
}
