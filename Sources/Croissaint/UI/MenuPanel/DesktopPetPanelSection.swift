// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import SwiftUI

/// The Desktop Pet section of the menu panel: the buddy care surface (stats,
/// feeding, bag, wild encounters happen on the desktop itself) as one of the
/// panel's navigation tabs, with the show-on-desktop switch at the top so the
/// walker can be sent home without a trip to Settings. Only exists while the
/// feature is installed; the section tab can be hidden from the panel layout
/// editor like any other.
struct DesktopPetPanelSection: View {
    var collapsible = true

    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.desktopPetEnabled) private var showOnDesktop = true

    var body: some View {
        PanelSection(.desktopPet,
                     title: FeatureStrings.desktopPet(L10n.shared.language).pageTitle,
                     collapsible: collapsible) {
            VStack(spacing: 10) {
                Toggle(strings.showOnDesktopToggle, isOn: $showOnDesktop)
                    .font(.system(size: 10.5, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(strings.showOnDesktopCaption)
                    .onChange(of: showOnDesktop) { _, _ in
                        DesktopPetService.shared.syncWithPreferences()
                    }

                PetCompanionView()
                    .environmentObject(PetState.shared)
            }
            .panelCard()
        }
    }

    private var strings: DesktopPetFeatureStrings {
        FeatureStrings.desktopPet(l10n.language)
    }
}
