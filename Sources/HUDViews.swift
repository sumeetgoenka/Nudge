//
//  HUDViews.swift
//  Nudge
//
//  Custom NSPanel / NSView / NSButton subclasses used by the HUD:
//    - HUDPanel:        borderless floating panel above all windows
//    - HUDContentView:  root view that handles click-through hit-testing
//    - PillButton:      rounded-pill NSButton used for minimized actions
//    - FlippedView:     NSView with isFlipped = true for top-down scroll content
//    - BlockRowView:    row with rounded highlight for the current block
//    - DragHandleView:  top strip used to move the window
//

import Cocoa

// MARK: - Expanded view theme

/// Colour palette for the expanded panel — deep indigo with violet accents.
/// Minimised view is unaffected; it keeps the original grey/white scheme.
enum Theme {
    // Text hierarchy  (warm lavender-whites)
    static let primary   = NSColor(red: 0.93, green: 0.91, blue: 0.98, alpha: 1.0)
    static let secondary = NSColor(red: 0.73, green: 0.71, blue: 0.83, alpha: 1.0)
    static let tertiary  = NSColor(red: 0.55, green: 0.53, blue: 0.67, alpha: 1.0)
    static let muted     = NSColor(red: 0.40, green: 0.38, blue: 0.52, alpha: 1.0)
    static let dim       = NSColor(red: 0.28, green: 0.26, blue: 0.40, alpha: 1.0)

    // Accent  (vibrant violet)
    static let accent    = NSColor(red: 0.56, green: 0.36, blue: 1.00, alpha: 1.0)

    // Surfaces  (accent-tinted glass)
    static let surface   = NSColor(red: 0.56, green: 0.36, blue: 1.00, alpha: 0.06)
    static let surfaceHi = NSColor(red: 0.56, green: 0.36, blue: 1.00, alpha: 0.12)
    static let border    = NSColor(red: 0.56, green: 0.36, blue: 1.00, alpha: 0.20)

    // Background overlay  (deep indigo tint over the blur)
    static let bgTint    = NSColor(red: 0.08, green: 0.05, blue: 0.20, alpha: 0.60)
}

// MARK: - HUD Panel

final class HUDPanel: NSPanel {
    /// Allows text-input focus while editing the schedule or the todo page.
    /// When flipped on the panel becomes key-capable and temporarily drops
    /// `.nonactivatingPanel` so NSTextField can actually receive keyboard
    /// events.  When flipped off the panel reverts to its non-activating,
    /// click-through default.
    var allowsKey: Bool = false {
        didSet {
            guard allowsKey != oldValue else { return }
            if allowsKey {
                styleMask.remove(.nonactivatingPanel)
                becomesKeyOnlyIfNeeded = false
            } else {
                styleMask.insert(.nonactivatingPanel)
                becomesKeyOnlyIfNeeded = true
                // Give up key status so the panel stops intercepting keys.
                resignKey()
            }
        }
    }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.isMovableByWindowBackground = false  // we manage drag manually
        self.hasShadow = true
        self.backgroundColor = .clear
        self.isOpaque = false
        // Above .floating; statusBar is one of the highest standard levels.
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        // Stay on every space and never appear in Mission Control / Exposé.
        self.collectionBehavior = [.canJoinAllSpaces,
                                   .fullScreenAuxiliary,
                                   .stationary,
                                   .ignoresCycle]
    }
}

// MARK: - Click-to-focus text field

/// NSTextField subclass that forces its window to become key and grabs first
/// responder on mouseDown.  This guarantees the field is editable even inside
/// a floating, non-activating panel.
final class ClickToFocusTextField: NSTextField {
    // Accept clicks even when the window is not key (first-mouse behaviour).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        // 1. Make the panel key-capable (drops .nonactivatingPanel).
        if let panel = window as? HUDPanel {
            panel.allowsKey = true
        }
        // 2. Temporarily promote to .regular so macOS routes keyboard
        //    events to this LSUIElement app, then activate.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // 3. Make the window key.
        window?.makeKeyAndOrderFront(nil)
        // 4. Start the field editor via super FIRST — this creates the
        //    NSTextView that actually handles typing.
        super.mouseDown(with: event)
        // 5. After super returns the field editor exists — force it as
        //    first responder in case AppKit skipped it.
        if let fe = window?.fieldEditor(true, for: self) {
            window?.makeFirstResponder(fe)
        }
    }

    override func becomeFirstResponder() -> Bool {
        // Ensure the panel is key-capable before we try to edit.
        if let panel = window as? HUDPanel {
            panel.allowsKey = true
        }
        return super.becomeFirstResponder()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        // Demote back to accessory so the dock icon disappears.
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Container view (click-through hit-testing)

final class HUDContentView: NSView {
    weak var dragHandle: NSView?
    var interactiveViews: [NSView] = []   // hit-testable in minimized mode
    var isExpanded: Bool = false

    override var isFlipped: Bool { false }

    // Minimized: only the drag handle + interactive controls receive clicks;
    // everywhere else passes through. Expanded: full standard hit testing.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isExpanded {
            let result = super.hitTest(point)
            // If the hit lands on a plain container view (not a control),
            // fall through to the drag handle so the window is draggable
            // from any empty area in expanded mode.
            if let result = result,
               !(result is NSControl) &&
               !(result is NSTextView) &&
               !(result is DragHandleView) &&
               !(result is NSScrollView) &&
               !(result is NSClipView) {
                if let handle = dragHandle {
                    let p = handle.convert(point, from: self)
                    if handle.bounds.contains(p) { return handle }
                }
            }
            return result
        }
        // `point` is in our (contentView) coordinate space. For each interactive
        // view, convert into its own coord space and check its bounds directly.
        // Returning the view itself is sufficient — none of our interactive
        // controls have meaningful subviews to drill into.
        for view in interactiveViews where !view.isHidden {
            let p = view.convert(point, from: self)
            if view.bounds.contains(p) {
                return view
            }
        }
        if let handle = dragHandle {
            let p = handle.convert(point, from: self)
            if handle.bounds.contains(p) { return handle }
        }
        return nil
    }
}

// MARK: - Pill button

/// Pill-style NSButton — rounded background, internal padding, hover opacity.
final class PillButton: NSButton {
    var hPadding: CGFloat = 9
    var minHeight: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 5
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + hPadding * 2, height: max(minHeight, s.height + 6))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.opacity = 0.85
    }
    override func mouseExited(with event: NSEvent) {
        layer?.opacity = 1.0
    }

    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeInActiveApp],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }
}

// MARK: - Scroll helpers

/// Flipped container so NSScrollView scrolls from the top down.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Block row

/// Row view used in the expanded Today list — supports a rounded background
/// highlight for the currently active block.
final class BlockRowView: NSView {
    var highlighted: Bool = false {
        didSet { updateHighlight() }
    }
    private let bg = CALayer()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(bg)
        bg.cornerRadius = 8
        bg.frame = bounds
        bg.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        bg.backgroundColor = NSColor.clear.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateHighlight() {
        bg.backgroundColor = highlighted
            ? Theme.accent.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Auto-batching grid stack

/// A vertical NSStackView that auto-groups its arranged children into
/// horizontal rows of `cols` items each. Use this for the calendar picker
/// grids — much simpler than NSGridView and avoids its layout quirks.
final class AutoGridStackView: NSStackView {
    let cols: Int
    init(cols: Int) {
        self.cols = cols
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func addArrangedSubview(_ view: NSView) {
        // If the last arranged subview is a non-full row, append to it.
        if let lastRow = arrangedSubviews.last as? NSStackView,
           lastRow.arrangedSubviews.count < cols {
            lastRow.addArrangedSubview(view)
            return
        }
        // Otherwise create a new row.
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        super.addArrangedSubview(row)
        // Stretch to our width so .fillEqually can divide it.
        row.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        row.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        row.addArrangedSubview(view)
    }
}

// MARK: - Sidebar item button

/// A custom NSButton drawn with a left accent bar + SF Symbol icon + label.
/// Click handling and target/action come from NSButton; the styling is fully
/// owned by this class so we don't fight NSButton's internal layout.
final class SidebarItemButton: NSButton {
    /// Stored separately so NSButton's own title machinery can't clobber it.
    let displayTitle: String
    let symbolName: String
    var isActive: Bool = false {
        didSet { needsDisplay = true }
    }

    init(title: String, symbolName: String) {
        self.displayTitle = title
        self.symbolName = symbolName
        super.init(frame: .zero)
        self.title = ""
        self.attributedTitle = NSAttributedString(string: "")
        self.bezelStyle = .inline
        self.isBordered = false
        self.imagePosition = .noImage
        self.wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 144, height: 36)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Background pill
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2),
                                  xRadius: 8, yRadius: 8)
        if isActive {
            Theme.surfaceHi.setFill()
        } else {
            NSColor.clear.setFill()
        }
        bgPath.fill()

        // Left accent bar (only when active)
        if isActive {
            let bar = NSBezierPath(roundedRect: NSRect(x: 4, y: 8, width: 3, height: bounds.height - 16),
                                   xRadius: 1.5, yRadius: 1.5)
            Theme.accent.setFill()
            bar.fill()
        }

        // SF Symbol icon
        let iconRect = NSRect(x: 14, y: (bounds.height - 16) / 2, width: 16, height: 16)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: isActive ? .semibold : .regular)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tint: NSColor = isActive ? Theme.primary : Theme.tertiary
            let tinted = img.copy() as! NSImage
            tinted.lockFocus()
            tint.set()
            let imgRect = NSRect(origin: .zero, size: tinted.size)
            imgRect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: iconRect)
        }

        // Label — use the stored displayTitle and draw at a point.
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isActive ? Theme.primary : Theme.secondary,
            .font: NSFont.systemFont(ofSize: 13, weight: isActive ? .semibold : .medium),
        ]
        let attrTitle = NSAttributedString(string: displayTitle, attributes: labelAttrs)
        let textSize = attrTitle.size()
        let textPoint = NSPoint(x: 40, y: (bounds.height - textSize.height) / 2)
        attrTitle.draw(at: textPoint)
    }
}

// MARK: - Progress ring

/// Circular progress indicator used in the Progress dashboard hero card.
/// Renders a track + a foreground arc filling 0..1 of the circumference.
final class ProgressRingView: NSView {
    var percent: CGFloat {
        didSet { rebuild() }
    }
    var trackColor: NSColor = Theme.surfaceHi
    var fillColor: NSColor = Theme.accent
    var lineWidth: CGFloat = 9

    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()

    init(percent: CGFloat) {
        self.percent = max(0, min(1, percent))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func rebuild() {
        let inset = lineWidth / 2 + 1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return }

        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        trackLayer.frame = bounds
        fillLayer.frame = bounds
        fillLayer.transform = CATransform3DIdentity

        // Track — full circle.
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius,
                            startAngle: 0, endAngle: 360)
        trackLayer.path = trackPath.cgPath
        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth = lineWidth

        // Fill — arc starting at the top (90°) sweeping clockwise.
        let pct = max(0, min(1, percent))
        if pct <= 0 {
            fillLayer.path = nil
        } else {
            let fillPath = NSBezierPath()
            // NSBezierPath: 0° = 3 o'clock, 90° = 12 o'clock, angles in degrees.
            // startAngle 90 → endAngle (90 - 360*pct), drawn clockwise.
            fillPath.appendArc(withCenter: center,
                               radius: radius,
                               startAngle: 90,
                               endAngle: CGFloat(90 - 360 * Double(pct)),
                               clockwise: true)
            fillLayer.path = fillPath.cgPath
        }
        fillLayer.fillColor = NSColor.clear.cgColor
        fillLayer.strokeColor = fillColor.cgColor
        fillLayer.lineWidth = lineWidth
        fillLayer.lineCap = .round
    }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var pts = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:           path.move(to: pts[0])
            case .lineTo:           path.addLine(to: pts[0])
            case .curveTo:          path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .cubicCurveTo:     path.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo: path.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:        path.closeSubpath()
            @unknown default:       break
            }
        }
        return path
    }
}

// MARK: - Drag handle

final class DragHandleView: NSView {
    var onDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        // Begin native window drag
        window?.performDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnded?()
    }
}
