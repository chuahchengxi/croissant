// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// AppKit describes a non-activating panel as a system dialog, which tiling
/// window managers track and list on whichever space is current. The shared
/// panel class is compiled here and created deferred, so no window is shown;
/// each floating surface's own file is read for the class it builds.
enum OverlayPanelTests {
    static func run(_ suite: TestSuite) {
        // The Clipboard History window keeps a title bar strip to drag it by.
        for style: NSWindow.StyleMask in [[.borderless, .nonactivatingPanel],
                                          [.titled, .closable, .fullSizeContentView, .nonactivatingPanel]] {
            let overlay = OverlayPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                                       styleMask: style, backing: .buffered, defer: true)
            suite.expect(overlay.accessibilitySubrole() == .unknown,
                         "a floating overlay describes itself as an undescribed window, so window managers skip it")
            suite.expect(overlay.accessibilityRole() == .window && overlay.isAccessibilityElement(),
                         "a floating overlay stays an accessible window for assistive technology")
        }

        // HUDs, previews, pickers and the menu's positioning helper: none is a
        // document window, and each floats over other apps' windows.
        let surfaces = [
            "Sources/Croissaint/App/AppDelegate.swift",
            "Sources/Croissaint/UI/PermissionGuideOverlay.swift",
            "Sources/Croissaint/UI/QuitProtection/QuitProtectionHUD.swift",
            "Sources/Croissaint/Services/QuickTools/QuickToolHUD.swift",
            "Sources/Croissaint/Services/QuickTools/QuickLauncherService.swift",
            "Sources/Croissaint/Services/QuickTools/CameraPreviewService.swift",
            "Sources/Croissaint/Services/QuickTools/RecentCaptureService.swift",
            "Sources/Croissaint/Services/QuickTools/ScreenshotSelectionController.swift",
            "Sources/Croissaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            "Sources/Croissaint/Services/QuickTools/ScreenshotPinController.swift",
            "Sources/Croissaint/Services/QuickTools/QRResultController.swift",
            "Sources/Croissaint/Services/QuickTools/ScratchpadService.swift",
            "Sources/Croissaint/Services/Snippets/SnippetLibraryService.swift",
            "Sources/Croissaint/Services/Clipboard/ClipboardHistoryService.swift",
            "Sources/Croissaint/Services/CommandBar/CommandBarService.swift",
            "Sources/Croissaint/Services/Switcher/AppSwitcher.swift",
            "Sources/Croissaint/Services/RadialMenu/RadialMenuService.swift",
            "Sources/Croissaint/Services/RadialMenu/RadialNowPlayingService.swift",
            "Sources/Croissaint/Services/DockPreview/DockPreviewService.swift",
            "Sources/Croissaint/Services/WindowLayout/WindowLayoutService.swift",
            "Sources/Croissaint/Services/DiskImageInstaller/DiskImageInstallerService.swift",
            "Sources/Croissaint/Services/Finder/FinderCutPaste.swift",
            "Sources/Croissaint/Services/Display/BrightnessOSD.swift",
            "Sources/Croissaint/Services/CleaningMode/CleaningModeManager.swift",
            "Sources/Croissaint/Services/Recorder/RecorderIndicator.swift",
        ]
        for path in surfaces {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            // KeyablePanel is the fork's shared OverlayPanel subclass.
            suite.expect(source.range(of: #"\b(Overlay|Keyable)Panel\(\s*contentRect|:\s*(Overlay|Keyable)Panel\b"#,
                                      options: .regularExpression) != nil
                         && !source.contains("NSPanel(contentRect")
                         && source.range(of: #"class \w+:\s*NSPanel\b"#, options: .regularExpression) == nil,
                         "\(path) builds its floating panels as overlays, which window managers do not list")
        }
    }
}
