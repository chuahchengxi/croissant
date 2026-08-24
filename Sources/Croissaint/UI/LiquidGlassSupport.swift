// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// Liquid Glass support.
//
// The systemwide Liquid Glass design (`.glassEffect`, the glass button
// styles, morphing `GlassEffectContainer`s) arrived with macOS 26, while this
// app still deploys to macOS 14. Everything here is therefore availability
// gated: on a Mac running 26 or newer the chrome below renders as genuine
// Liquid Glass, and everywhere else it keeps the hand-drawn vibrancy the app
// has always had. The animations are not gated — springy presses and hovers
// read well against either material.

/// Scales a button's label down while pressed and springs it back on release.
///
/// The default `.plain` style gives no physical feedback at all, which every
/// hand-drawn chip in the floating panels suffered from. This restores the
/// tactile dip without touching each chip's own visuals.
struct SpringPressButtonStyle: ButtonStyle {
    /// How far the label dips while held down.
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        PressFeedback(label: configuration.label, scale: scale,
                      isPressed: configuration.isPressed)
    }

    /// The state lives one view down so the spring owns it; driving the scale
    /// straight off `isPressed` would track the gesture's own timing instead.
    /// When the press flips, SwiftUI rebuilds this view with the new flag,
    /// `onChange` copies it into animated state, and the dip springs both ways.
    private struct PressFeedback<Label: View>: View {
        let label: Label
        var scale: CGFloat
        var isPressed: Bool

        @State private var dipped = false

        var body: some View {
            label
                .scaleEffect(dipped ? scale : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.55),
                           value: dipped)
                .onChange(of: isPressed) { _, pressed in
                    dipped = pressed
                }
        }
    }
}

/// One small icon chip used across the floating panels (shelf pin/close,
/// trash, HUD dismiss buttons).
///
/// On macOS 26 the chip is real interactive Liquid Glass; when the call site
/// provides a namespace and id (`glassID`/`in:`), neighbouring chips inside a
/// shared `GlassEffectContainer` melt into each other as the pointer crosses
/// them, the signature liquid behavior. On older systems the chip draws the
/// same circles those panels shipped with, so nothing changes visually except
/// the added hover lift and springy press.
struct GlassIconButton: View {
    enum ChipShape {
        case circle
        case rounded(CGFloat)
    }

    let systemImage: String
    /// Accent-tinted state (a pinned shelf, an enabled toggle).
    var isActive = false
    /// Forces a colored chip (the trash's red) on both materials.
    var tint: Color? = nil
    var helpText: String?
    var accessibilityLabel: String?
    var width: CGFloat = 30
    var height: CGFloat = 30
    var iconSize: CGFloat = 13
    var shape: ChipShape = .circle
    /// Identity within the call site's `GlassEffectContainer` (macOS 26+).
    var glassID: String? = nil
    var glassNamespace: Namespace.ID? = nil
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                glassChip
            } else {
                legacyChip
            }
            #else
            legacyChip
            #endif
        }
        .onHover { hovered = $0 }
        .help(helpText ?? "")
        .accessibilityLabel(accessibilityLabel ?? helpText ?? systemImage)
    }

    // MARK: macOS 26+

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glassChip: some View {
        Button(action: action) {
            chipLabel
        }
        .buttonStyle(SpringPressButtonStyle(scale: 0.88))
        .foregroundStyle(labelColor)
        .glassEffect(glassMaterial, in: shapePath)
        .modifier(GlassChipIdentity(id: glassID, namespace: glassNamespace))
    }

    @available(macOS 26.0, *)
    private var glassMaterial: Glass {
        var material = Glass.regular.interactive()
        if let tint { material = material.tint(tint) }
        return material
    }

    /// Applies the morphing identity when the call site participates in a
    /// `GlassEffectContainer`; standalone chips skip it.
    @available(macOS 26.0, *)
    private struct GlassChipIdentity: ViewModifier {
        var id: String?
        var namespace: Namespace.ID?

        func body(content: Content) -> some View {
            if let id, let namespace {
                content.glassEffectID(id, in: namespace)
            } else {
                content
            }
        }
    }
    #endif

    // MARK: Fallback (macOS 14–25)

    private var legacyChip: some View {
        Button(action: action) {
            chipLabel
                .background(shapePath.fill(legacyFill))
                .overlay(shapePath.stroke(legacyStroke, lineWidth: 1))
        }
        .buttonStyle(SpringPressButtonStyle())
        .foregroundStyle(labelColor)
    }

    private var legacyFill: Color {
        if let tint {
            return tint.opacity(hovered ? 0.20 : 0.07)
        }
        if isActive {
            return Color.accentColor.opacity(hovered ? 0.30 : 0.20)
        }
        return Color.white.opacity(hovered ? 0.18 : 0.11)
    }

    private var legacyStroke: Color {
        if let tint {
            return tint.opacity(hovered ? 0.34 : 0.12)
        }
        if isActive {
            return Color.accentColor.opacity(0.65)
        }
        return Color.white.opacity(hovered ? 0.75 : 0.32)
    }

    // MARK: Shared pieces

    private var chipLabel: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .frame(width: width, height: height)
            .contentShape(shapePath)
    }

    private var labelColor: Color {
        if let tint { return tint }
        if isActive { return Color.accentColor }
        return Color.secondary
    }

    private var shapePath: AnyShape {
        switch shape {
        case .circle:
            AnyShape(Circle())
        case .rounded(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

// MARK: - Small-surface glass

extension View {
    /// The backdrop for small floating content (confirmation HUDs, the
    /// brightness OSD): genuine Liquid Glass on macOS 26, the `.regularMaterial`
    /// those surfaces shipped with on older systems. Same silhouette either
    /// way, so callers pass their shape and nothing else changes.
    @ViewBuilder
    func hudGlassBackground<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
        #else
        self.background(.regularMaterial, in: shape)
        #endif
    }
}
