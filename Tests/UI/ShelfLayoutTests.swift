// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

/// Real AppKit/SwiftUI sizing checks; run in the isolated app made by test-shelf-layout.sh.
@main
struct ShelfLayoutTests {
    @MainActor static func main() throws {
        guard let identity = Bundle.main.bundleIdentifier,
              identity.hasPrefix("com.croissaint.tests.shelf-layout.") else {
            fatalError("Run Tools/test-shelf-layout.sh to isolate user data")
        }
        let defaults = UserDefaults.standard
        let fixture = ShelfPersistedItem(id: UUID(), kind: .text,
                                         title: "Layout regression", text: "Layout regression")
        defaults.setVolatileDomain([
            DefaultsKey.shelfEnabled: true,
            DefaultsKey.shelfDropZoneEnabled: true,
            AppFeature.shelf.availabilityKey: true,
            DefaultsKey.shelfItems: try JSONEncoder().encode([fixture])
        ], forName: UserDefaults.argumentDomain)
        defer { defaults.removePersistentDomain(forName: identity) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let shelf = ShelfService.shared
        func settle() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        }
        let deadline = Date().addingTimeInterval(5)
        while shelf.itemCount == 0 && Date() < deadline { settle() }
        precondition(shelf.itemCount == 1, "Text fixture failed to restore")
        func visiblePanel() -> NSWindow {
            let panels = app.windows.filter { $0 is NSPanel && $0.isVisible }
            precondition(panels.count == 1, "Expected exactly one visible shelf")
            return panels[0]
        }
        func checkSize(_ size: NSSize) {
            precondition(size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0,
                         "Invalid shelf dimensions: \(size)")
        }
        shelf.syncDockedShelf()
        settle()
        let pillSize = visiblePanel().frame.size
        checkSize(pillSize)
        precondition(pillSize.width < 304 && pillSize.height < 100, "Pill did not collapse")
        for _ in 0..<40 {
            shelf.expandDocked()
            settle()
            let card = visiblePanel()
            let cardSize = card.frame.size
            checkSize(cardSize)
            precondition(cardSize.width >= 304 && cardSize.height >= 188,
                         "Expanded shelf was clipped: \(cardSize)")
            for _ in 0..<5 { shelf.syncDockedShelf() }
            settle()
            precondition(card.frame.size == cardSize, "Repeated sync changed expanded size")
            shelf.collapseDocked()
            settle()
            precondition(visiblePanel().frame.size == pillSize, "Pill did not return to its original size")
        }
        shelf.summon()
        settle()
        precondition(shelf.isVisible, "Classic shelf did not open")
        checkSize(visiblePanel().frame.size)
        shelf.hide()
        settle()
        precondition(!shelf.isVisible, "Classic shelf did not hide")
        precondition(visiblePanel().frame.size == pillSize, "Docked shelf did not return")
        app.windows.forEach { $0.orderOut(nil) }
        print("Shelf layout passed: 40 expand/collapse cycles, 200 repeated syncs, classic open/close; pill \(pillSize)")
    }
}
