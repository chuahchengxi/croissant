// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit

/// Hides macOS's privacy indicators (the purple screen-recording dot and its
/// camera/microphone siblings) from the menu bar.
///
/// How they work on modern macOS: while any process captures, the Window
/// Server floats small `StatusIndicator`-named windows near the right end of
/// the menu bar at an extremely high window level. They are owned by the
/// Window Server itself, so no Accessibility or private API can move them —
/// which is exactly why menu-bar managers stopped being able to hide them.
///
/// The cloak instead draws a patch *above* them: a borderless panel one level
/// higher, filled with a live sample of the neighbouring menu-bar pixels, so
/// the dot reads as gone. Nothing about capture itself is affected; this only
/// touches what the user sees. It needs no permissions of its own.
///
/// macOS 26 closed this off. The indicator is now composited above every level
/// an app window can reach: a patch at `kCGMaximumWindowLevel` (2147483631),
/// or even at `Int32.max`, is placed correctly and still has the dot drawn on
/// top of it. There is no level left to win from, so on 26 and newer the
/// service stays down rather than running a timer and a screen capture every
/// second for a patch that cannot cover anything — capture that, being capture,
/// would itself keep the screen-recording dot lit.
final class IndicatorCloakService {
    static let shared = IndicatorCloakService()

    /// False where the OS composites the indicators above any window we can
    /// make. Checked before anything starts, and read by Settings so the
    /// toggle can say why it is off rather than silently doing nothing.
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return false }
        return true
    }

    /// The Window Server names every privacy indicator window this way.
    private static let indicatorName = "StatusIndicator"
    /// One above the indicators' own level (2147483630) so the patch wins.
    private static let cloakLevel: NSWindow.Level = NSWindow.Level(rawValue: 2_147_483_631)
    /// Padding so anti-aliased edges never peek out around the sampled fill.
    private static let pad: CGFloat = 4

    private var timer: Timer?
    private var panels: [String: NSPanel] = [:]

    private init() {}

    func syncWithPreferences() {
        let enabled = Self.isSupported
            && UserDefaults.standard.bool(forKey: DefaultsKey.privacyIndicatorCloakEnabled)
        if enabled { start() } else { stop() }
    }

    func start() {
        guard Self.isSupported, timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.reconcile()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        reconcile()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    // MARK: - Detection

    private struct Spot: Equatable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        var key: String { "\(Int(x)),\(Int(y)),\(Int(width))x\(Int(height))" }
    }

    /// Every on-screen privacy indicator position right now.
    private func activeSpots() -> [Spot] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        var seen = Set<UInt32>()
        var spots: [Spot] = []
        for info in list {
            // Owner name check first: the indicators belong to the Window
            // Server (pid 0), unlike regular status items owned by ControlCenter.
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Window Server",
                  let name = info[kCGWindowName as String] as? String,
                  name == Self.indicatorName,
                  let num = info[kCGWindowNumber as String] as? UInt32,
                  seen.insert(num).inserted,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let w = b["Width"], let h = b["Height"],
                  w > 2, h > 2
            else { continue }
            spots.append(Spot(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: w, height: h))
        }
        return spots
    }

    // MARK: - Cloaking

    /// Shows a patch over each indicator and retires patches whose indicator
    /// has gone away.
    private func reconcile() {
        let spots = activeSpots()
        let wanted = Set(spots.map(\.key))

        for key in panels.keys where !wanted.contains(key) {
            panels.removeValue(forKey: key)?.orderOut(nil)
        }
        for spot in spots where panels[spot.key] == nil {
            let panel = makePanel(for: spot)
            panels[spot.key] = panel
            panel.orderFrontRegardless()
        }

        // Refresh the sampled fill occasionally: the menu bar's vibrancy
        // shifts with wallpaper focus changes underneath it.
        if !spots.isEmpty {
            for panel in panels.values {
                panel.contentView?.needsDisplay = true
            }
        }
    }

    private func makePanel(for spot: Spot) -> NSPanel {
        let frame = CGRect(x: spot.x - Self.pad,
                           y: spot.y - Self.pad,
                           width: spot.width + Self.pad * 2,
                           height: spot.height + Self.pad * 2)
        let panel = NSPanel(contentRect: appKitFrame(from: frame),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = Self.cloakLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = MenuBarPatchView(frame: panel.frame)
        return panel
    }

    /// CG window bounds are top-left global; AppKit frames are bottom-left.
    private func appKitFrame(from cg: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? cg.maxY
        return NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }
}

// MARK: - Sampled patch content

/// Draws the strip of menu bar just beside the indicator over the indicator's
/// footprint, refreshed on a beat so wallpaper/vibrancy changes keep up.
private final class MenuBarPatchView: NSView {
    private var refreshTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    deinit { refreshTimer?.invalidate() }

    override func draw(_ dirtyRect: NSRect) {
        guard let sample = sampleImage(), let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(sample, in: bounds)
    }

    /// Grabs a slice of the menu bar next to this view (same rows, offset
    /// sideways), mirrored horizontally so lighting gradients stay natural.
    private func sampleImage() -> CGImage? {
        let screenFrame = window?.frame ?? frame
        let displayID = screenForFrame(screenFrame)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID ?? CGMainDisplayID()

        let sliceWidth = max(24, frame.width)
        let global = convertToGlobalScreen()
        // Sample to the left; fall back to the right when hugging the corner.
        let sampleX = global.minX - sliceWidth - 2 >= 0
            ? global.minX - sliceWidth - 2
            : global.maxX + 2

        // AppKit Y (bottom-left origin of the primary screen) -> CG top-left.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let cgYTopLeft = primaryHeight - (global.minY + global.height)

        let rect = CGRect(x: sampleX, y: cgYTopLeft, width: sliceWidth, height: global.height)
        return CGDisplayCreateImage(displayID, rect: rect)
    }

    /// This view's frame in global AppKit coordinates.
    private func convertToGlobalScreen() -> CGRect {
        guard let window else { return frame }
        return window.convertToScreen(convert(window.contentView?.bounds ?? bounds, to: nil))
    }

    private func screenForFrame(_ frame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
    }
}
