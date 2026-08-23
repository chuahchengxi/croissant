// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Brings the desktop companion to life and puts it back to sleep. The
/// FeatureRuntime binding calls `syncWithPreferences()` at launch (only for an
/// available feature) and on every install/uninstall, so nothing here runs —
/// no timers, no panels, no sprite prefetch — while the feature sits
/// uninstalled or its show-on-desktop switch is off.
final class DesktopPetService: ObservableObject {
    static let shared = DesktopPetService()

    @Published private(set) var isRunning = false

    private init() {}

    func syncWithPreferences() {
        let shouldRun = AppFeature.desktopPet.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.desktopPetEnabled)
        if shouldRun { start() } else { stop() }
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true

        let pet = PetState.shared
        pet.startClock()
        AppFeatureRuntimeSupport.noteLoaded(.desktopPet)
        DesktopPetController.shared.start(pet: pet)
        WildSpawnController.shared.start(pet: pet)
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        WildSpawnController.shared.stop()
        DesktopPetController.shared.stop()
        PetState.shared.stopClock()
    }
}

/// Small indirection so the service can register itself with the feature
/// runtime's session bookkeeping without the runtime knowing about pets.
enum AppFeatureRuntimeSupport {
    static func noteLoaded(_ feature: AppFeature) {
        FeatureRuntime.shared.markLoadedThisSession(feature)
    }
}
