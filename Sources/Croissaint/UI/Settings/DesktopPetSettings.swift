// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import SwiftUI

struct DesktopPetSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DesktopPetService.shared
    @AppStorage(DefaultsKey.desktopPetEnabled) private var showOnDesktop = true
    @AppStorage(DefaultsKey.desktopPetBlinks) private var blinks = true
    @AppStorage(DefaultsKey.desktopPetNotifications) private var mirrorsNotifications = false
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        Form {
            Section {
                Toggle(strings.showOnDesktopToggle, isOn: $showOnDesktop)
                    .onChange(of: showOnDesktop) { _, _ in
                        DesktopPetService.shared.syncWithPreferences()
                    }
                Text(strings.showOnDesktopCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showOnDesktop, service.isRunning {
                    Label(strings.activeNow, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Toggle(strings.blinkToggle, isOn: $blinks)
                Text(strings.blinkCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(strings.notificationsToggle, isOn: $mirrorsNotifications)
                Text(strings.notificationsCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only once it's asked for: the permission is what makes the
                // feed work, and there is no prompt for it.
                if mirrorsNotifications, !permissions.fullDiskAccess {
                    FullDiskAccessNote(reason: strings.notificationsFDANote)
                }
            }

            if service.isRunning {
                Section(strings.companionSection) {
                    PetCompanionView()
                        .environmentObject(PetState.shared)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var strings: DesktopPetFeatureStrings {
        FeatureStrings.desktopPet(l10n.language)
    }
}
