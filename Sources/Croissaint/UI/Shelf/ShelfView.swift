// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Contents of the floating shelf panel: a header (a move handle plus actions)
/// and the item tiles. Dropping onto the card adds items; the tiles themselves
/// are AppKit, so they can drag several selected items out at once.
struct ShelfView: View {
    /// The top-right button. The floating shelf closes; the docked shelf
    /// collapses to its pill instead of vanishing.
    var dismissSystemImage: String = "xmark"
    var dismissHelp: String? = nil
    var onDismiss: (() -> Void)? = nil
    /// Called with the provider count after a drop is accepted, so the docked
    /// shelf can flash and settle back to its pill.
    var onAccept: ((Int) -> Void)? = nil
    /// The docked shelf shows the brand mark as a quiet watermark, so it reads
    /// as the app's own tray rather than a plain floating card.
    var brandWatermark: Bool = false

    @EnvironmentObject private var shelf: ShelfService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var targeted = false
    /// Shared Liquid Glass space for the header chips; on macOS 26 they melt
    /// into each other as the pointer crosses between them.
    @Namespace private var headerGlass

    private static let dropTypes: [UTType] = [.fileURL, .image, .url, .text, .plainText]
    private static let panelWidth: CGFloat = 304
    private static let tileAreaHeight: CGFloat = 188

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            tiles
            if !shelf.items.isEmpty {
                bottomBar
            }
        }
        .padding(14)
        .frame(width: Self.panelWidth)
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 18)
                if brandWatermark { brandWatermarkLayer }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: isDropTargeted ? 2 : 1)
        )
        .overlay(alignment: .topLeading) {
            topMoveHandle
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: shelf.items)
        .onHover { inside in
            shelf.setPointerInsidePanel(inside)
        }
        .onChange(of: targeted) { _, isTargeted in
            shelf.setDropTargeted(isTargeted)
        }
        .onDrop(of: Self.dropTypes, isTargeted: $targeted) { providers in
            let accepted = shelf.accept(providers: providers)
            if accepted {
                shelf.noteInteraction()
                onAccept?(providers.count)
            }
            return accepted
        }
    }

    private var isDropTargeted: Bool {
        targeted || shelf.dropTargeted
    }

    /// The official mark, large and faint in the corner: unmistakably ours,
    /// never loud enough to fight the tiles.
    private var brandWatermarkLayer: some View {
        BrandMark(width: 128, tint: colorScheme == .light ? Color.black : Color.white)
            .opacity(colorScheme == .light ? 0.05 : 0.08)
            .rotationEffect(.degrees(-8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 34, y: 26)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 7) {
            // Drag this region to move the panel; the tiles below stay free to
            // start item drags.
            HStack(spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !shelf.items.isEmpty {
                    Text("\(shelf.itemCount)")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .overlay(WindowMoveHandle())

            headerControls
        }
    }

    /// The trailing chips. On macOS 26 they live in one shared glass space so
    /// pin and close read as droplets of the same material, merging as the
    /// pointer crosses them; older systems draw the same two chips separately.
    @ViewBuilder
    private var headerControls: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { chips }
        } else {
            chips
        }
        #else
        chips
        #endif
    }

    @ViewBuilder
    private var chips: some View {
        if !brandWatermark {
            GlassIconButton(systemImage: shelf.isPinned ? "pin.fill" : "pin",
                            isActive: shelf.isPinned,
                            helpText: shelf.isPinned ? l10n.s.shelfUnpin : l10n.s.shelfPin,
                            accessibilityLabel: shelf.isPinned ? l10n.s.shelfUnpin : l10n.s.shelfPin,
                            iconSize: 12,
                            glassID: "shelf-pin",
                            glassNamespace: headerGlass) {
                shelf.togglePin()
            }
        }
        GlassIconButton(systemImage: dismissSystemImage,
                        helpText: dismissHelp ?? l10n.s.menuClose,
                        iconSize: 13,
                        glassID: "shelf-close",
                        glassNamespace: headerGlass) {
            (onDismiss ?? { shelf.hide() })()
        }
    }

    private var topMoveHandle: some View {
        WindowMoveHandle(acceptsDrops: true)
            .frame(width: Self.panelWidth - (brandWatermark ? 58 : 96), height: 55)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Text(l10n.s.shelfHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if canAirDrop { airDropButton }
            clearButton
        }
        .frame(minHeight: 30)
    }

    /// Sends the shelf straight on: park a few files here, then hand the whole
    /// pile to someone without a detour through Finder. Scoped to the
    /// selection when there is one, otherwise everything on the shelf. Hidden
    /// rather than disabled when nothing on the shelf is a file, since text and
    /// link tiles have nothing AirDrop can carry.
    private var airDropButton: some View {
        GlassIconButton(systemImage: "square.and.arrow.up",
                        helpText: l10n.s.shelfActionAirDrop,
                        width: 42,
                        height: 28,
                        iconSize: 12,
                        shape: .rounded(6)) {
            airDropAction()
        }
    }

    private var canAirDrop: Bool {
        shelf.hasFileItems && NSSharingService(named: .sendViaAirDrop) != nil
    }

    private var clearButton: some View {
        GlassIconButton(systemImage: shelf.selection.isEmpty ? "trash" : "trash.fill",
                        tint: .red,
                        helpText: shelf.selection.isEmpty ? l10n.s.shelfClearAll : l10n.s.shelfRemoveSelected,
                        width: 42,
                        height: 28,
                        iconSize: 12,
                        shape: .rounded(6)) {
            trashAction()
        }
    }

    private var title: String {
        shelf.selection.isEmpty
            ? l10n.s.shelfTitle
            : String(format: l10n.s.shelfSelectedFormat, shelf.selection.count)
    }

    @ViewBuilder
    private var tiles: some View {
        if shelf.items.isEmpty {
            emptyState
        } else {
            ShelfTilesView(items: shelf.visibleItems,
                           selection: shelf.selection,
                           expandedBatches: shelf.expandedBatches,
                           revealID: shelf.revealTargetID,
                           revealSerial: shelf.addSerial)
                .frame(height: Self.tileAreaHeight)
        }
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.secondary.opacity(0.4))
            .frame(height: Self.tileAreaHeight)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 21))
                        .foregroundStyle(.secondary)
                    Text(l10n.s.shelfEmpty)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            )
            .overlay(WindowMoveHandle(acceptsDrops: true))
    }

    private func airDropAction() {
        let urls = shelf.fileURLsForShelfActions()
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        shelf.noteInteraction()
        // The picker is an ordinary window of ours, so the app has to be front
        // for it to come up in front of whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    private func trashAction() {
        if shelf.selection.isEmpty {
            shelf.clear()
        } else {
            shelf.removeItems(Array(shelf.selection))
        }
    }
}
