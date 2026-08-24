// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let spriteCacheDidUpdate = Notification.Name("PokePal.spriteCacheDidUpdate")
    static let pokePalCelebrate = Notification.Name("PokePal.celebrate")
    static let pokePalToast = Notification.Name("PokePal.toast")
}

enum PetItemKind: String, Codable, CaseIterable {
    case pokeBall
    case greatBall
    case ultraBall
    case berry
    case everStone

    var displayName: String {
        switch self {
        case .pokeBall: return "Poké Ball"
        case .greatBall: return "Great Ball"
        case .ultraBall: return "Ultra Ball"
        case .berry: return "Oran Berry"
        case .everStone: return "Ever Stone"
        }
    }
}

enum PetMood {
    case great, okay, sad, critical, sleeping

    var text: String {
        switch self {
        case .great:
            return ["is thriving!", "loves this!", "feels amazing!", "is super happy!"].randomElement()!
        case .okay:
            return ["is doing alright.", "is chilling.", "wouldn't mind a snack."].randomElement()!
        case .sad:
            return ["is feeling lonely...", "wants attention...", "is getting hungry..."].randomElement()!
        case .critical:
            return ["needs help NOW!", "isn't doing so well!", "misses you dearly!"].randomElement()!
        case .sleeping:
            return ["is fast asleep. Zzz...", "is dreaming of berries...", "is recharging energy..."].randomElement()!
        }
    }
}

struct PetSnapshot: Codable {
    var species: String?
    var name: String = ""
    var hunger: Double = 80
    var happiness: Double = 80
    var energy: Double = 90
    var xp: Double = 0
    var sleeping = false
    var lastTick = Date()
    var createdAt = Date()
    var desktopVisible: Bool?
    var posX: Double?
    var posY: Double?
    var caughtCount: Int?
    /// National Dex ids of every wild species ever caught; each one unlocks
    /// its catalog entry as a selectable buddy.
    var caughtSpecies: [Int]?
    var inventory: [String: Int]?
    var activeBall: String?
    var coins: Int?
    /// True while the buddy holds an Ever Stone (shop-only item): its stage is
    /// frozen so it stops evolving until the stone is put down.
    var evolutionHeld: Bool?
    /// The stage the buddy was at when the stone was picked up.
    var frozenStage: Int?
}

final class PetState: ObservableObject {
    static let shared = PetState()

    @Published private(set) var snapshot: PetSnapshot

    private(set) var saveURL: URL
    private var timer: Timer?

    /// Creates the buddy store under the app's own container, carrying over a
    /// pet raised in the standalone PokePal app when one exists.
    private static func resolveSaveURL() -> URL {
        let base = PrivateFileStore.containerURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DesktopPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("pet.json")

        if !FileManager.default.fileExists(atPath: url.path) {
            let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PokePal/pet.json")
            if let data = try? Data(contentsOf: legacy) {
                try? data.write(to: url, options: .atomic)
            }
        }
        return url
    }

    init() {
        saveURL = Self.resolveSaveURL()

        if let data = try? Data(contentsOf: saveURL),
           let snap = try? JSONDecoder().decode(PetSnapshot.self, from: data) {
            snapshot = snap
        } else {
            snapshot = PetSnapshot()
        }

        // Dedenne is the default companion.
        if snapshot.species == nil {
            snapshot.species = "dedenne"
            snapshot.name = "Dedenne"
        }

        // Starter pack for first launch.
        if snapshot.inventory == nil {
            snapshot.inventory = [
                PetItemKind.pokeBall.rawValue: 10,
                PetItemKind.greatBall.rawValue: 3,
                PetItemKind.ultraBall.rawValue: 1,
                PetItemKind.berry.rawValue: 5
            ]
        }

        applyOfflineDecay()
    }

    /// Starts the care simulation. Called by DesktopPetService when the feature
    /// comes to life, so an uninstalled feature leaves no timers behind.
    func startClock() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        if let key = snapshot.species, let def = SpeciesDef.lookup(key) {
            SpriteCache.prefetch(ids: def.spriteIDs) { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    /// Stops the simulation and drops the shared instance's timers, so an
    /// uninstalled or disabled feature costs nothing while it sits idle.
    func stopClock() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Derived

    var species: SpeciesDef? {
        snapshot.species.flatMap { SpeciesDef.lookup($0) }
    }

    /// The buddy's display name. A nickname the player typed sticks; otherwise
    /// the name tracks the current evolution stage (Rowlet -> Dartrix -> Decidueye).
    var name: String {
        get {
            guard let s = species else { return snapshot.name }
            if snapshot.name.isEmpty || s.names.contains(snapshot.name) { return s.name(at: stage) }
            return snapshot.name
        }
        set {
            snapshot.name = newValue
            save()
        }
    }

    var level: Int { min(99, Int(snapshot.xp / 100) + 1) }
    var levelProgress: Double { (snapshot.xp.truncatingRemainder(dividingBy: 100)) / 100 }

    var stage: Int {
        guard let s = species else { return 0 }
        let natural = min(level >= 14 ? 2 : (level >= 6 ? 1 : 0), s.evoIDs.count - 1)
        // An Ever Stone freezes the buddy at the stage it was when picked up;
        // it can never fall behind the level-based stage, only hold it back.
        if evolutionBlocked, let frozen = snapshot.frozenStage {
            return min(natural, frozen)
        }
        return natural
    }

    /// True while an Ever Stone is held (and one is actually in the bag).
    var evolutionBlocked: Bool {
        snapshot.evolutionHeld == true && count(of: .everStone) > 0
    }

    var dexID: Int? { species?.evoIDs[stage] }

    /// Level at which the next stage unlocks, nil once the chain is exhausted
    /// or an Ever Stone is holding evolution back.
    var nextEvolutionLevel: Int? {
        guard !evolutionBlocked else { return nil }
        guard let s = species, stage < s.evoIDs.count - 1 else { return nil }
        return stage == 0 ? 6 : 14
    }

    /// Name of the stage the buddy is growing into, nil at the final stage.
    var nextEvolutionName: String? {
        guard let s = species, stage < s.names.count - 1 else { return nil }
        return s.names[stage + 1]
    }

    var mood: PetMood {
        if snapshot.sleeping { return .sleeping }
        if snapshot.hunger <= 0 || snapshot.energy <= 0 || snapshot.happiness <= 0 { return .critical }
        let avg = (snapshot.hunger + snapshot.happiness + snapshot.energy) / 3
        return avg >= 65 ? .great : (avg >= 35 ? .okay : .sad)
    }

    // MARK: - Actions

    /// Swap buddy at any time. All account progress (XP, level, items,
    /// coins, catches) carries over — only the companion changes.
    func switchTo(_ key: String) {
        guard let def = SpeciesDef.lookup(key), snapshot.species != key else { return }
        let fresh = snapshot.species == nil
        snapshot.species = def.key
        snapshot.name = ""
        // A new buddy doesn't inherit the old one's Ever Stone.
        snapshot.evolutionHeld = false
        snapshot.frozenStage = nil
        if fresh {
            snapshot.hunger = 85
            snapshot.happiness = 85
            snapshot.energy = 95
            snapshot.xp = 0
            snapshot.sleeping = false
        }
        snapshot.lastTick = Date()
        save()
        SpriteCache.prefetch(ids: def.spriteIDs) { [weak self] in
            self?.objectWillChange.send()
        }
        objectWillChange.send()
    }

    enum FeedOutcome { case ate, full, noBerries }

    func feed() -> FeedOutcome {
        guard snapshot.species != nil else { return .noBerries }
        if snapshot.sleeping { snapshot.sleeping = false }
        guard snapshot.hunger < 99 else { return .full }
        guard consume(.berry) else { return .noBerries }
        snapshot.hunger += 26
        snapshot.happiness += 4
        snapshot.xp += 5
        maybeFindItem()
        normalizeAndSave()
        return .ate
    }

    @discardableResult
    func play() -> Bool {
        guard snapshot.species != nil else { return false }
        if snapshot.sleeping { snapshot.sleeping = false }
        guard snapshot.energy >= 15 else { return false }
        snapshot.happiness += 22
        snapshot.energy -= 14
        snapshot.hunger -= 6
        snapshot.xp += 5
        maybeFindItem()
        normalizeAndSave()
        return true
    }

    @discardableResult
    func pet() -> Bool {
        guard snapshot.species != nil, !snapshot.sleeping else { return false }
        snapshot.happiness += 2.5
        snapshot.xp += 1
        maybeFindItem()
        normalizeAndSave()
        return true
    }

    func toggleSleep() {
        guard snapshot.species != nil else { return }
        snapshot.sleeping.toggle()
        normalizeAndSave()
    }

    // MARK: - Inventory

    func count(of kind: PetItemKind) -> Int {
        snapshot.inventory?[kind.rawValue] ?? 0
    }

    func addItem(_ kind: PetItemKind, _ amount: Int = 1) {
        var inv = snapshot.inventory ?? [:]
        inv[kind.rawValue, default: 0] += amount
        snapshot.inventory = inv
        save()
        objectWillChange.send()
    }

    @discardableResult
    func consume(_ kind: PetItemKind) -> Bool {
        guard count(of: kind) > 0 else { return false }
        var inv = snapshot.inventory ?? [:]
        inv[kind.rawValue, default: 0] -= 1
        snapshot.inventory = inv
        save()
        objectWillChange.send()
        return true
    }

    var activeBall: PetItemKind {
        PetItemKind(rawValue: snapshot.activeBall ?? "") ?? .pokeBall
    }

    func setActiveBall(_ kind: PetItemKind) {
        snapshot.activeBall = kind.rawValue
        save()
        objectWillChange.send()
    }

    /// Small chance to find an item after caring for the buddy.
    private func maybeFindItem() {
        guard Double.random(in: 0..<1) < 0.12 else { return }
        let roll = Double.random(in: 0..<1)
        let found: PetItemKind
        switch roll {
        case ..<0.50: found = .pokeBall
        case ..<0.80: found = .berry
        case ..<0.95: found = .greatBall
        default: found = .ultraBall
        }
        addItem(found, 1)
        NotificationCenter.default.post(
            name: .pokePalToast, object: nil,
            userInfo: ["message": "\(name) found a \(found.displayName)!"]
        )
    }

    func reset() {
        snapshot = PetSnapshot()
        snapshot.species = "dedenne"
        snapshot.name = "Dedenne"
        snapshot.inventory = [
            PetItemKind.pokeBall.rawValue: 10,
            PetItemKind.greatBall.rawValue: 3,
            PetItemKind.ultraBall.rawValue: 1,
            PetItemKind.berry.rawValue: 5
        ]
        save()
        objectWillChange.send()
    }

    /// Bonus when the buddy successfully fetches an app for you.
    @discardableResult
    func rewardFetch() -> Bool {
        guard snapshot.species != nil else { return false }
        if snapshot.sleeping { snapshot.sleeping = false }
        snapshot.happiness += 2
        snapshot.xp += 3
        normalizeAndSave()
        return true
    }

    var coinBalance: Int { snapshot.coins ?? 0 }

    func addCoins(_ amount: Int) {
        guard amount > 0 else { return }
        snapshot.coins = coinBalance + amount
        save()
        objectWillChange.send()
    }

    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard coinBalance >= amount else { return false }
        snapshot.coins = coinBalance - amount
        save()
        objectWillChange.send()
        return true
    }

    /// Reward for catching a wild pokemon, plus item drops. The caught
    /// species is remembered so it becomes a selectable buddy.
    @discardableResult
    func catchReward(speciesID: Int? = nil) -> Bool {
        guard snapshot.species != nil else { return false }
        if snapshot.sleeping { snapshot.sleeping = false }
        snapshot.happiness += 8
        snapshot.xp += 12
        snapshot.caughtCount = (snapshot.caughtCount ?? 0) + 1
        if let speciesID {
            var caught = snapshot.caughtSpecies ?? []
            if !caught.contains(speciesID) {
                caught.append(speciesID)
                snapshot.caughtSpecies = caught
            }
        }
        addItem(.pokeBall, 2)
        addItem(.berry, 1)
        if Double.random(in: 0..<1) < 0.25 { addItem(.greatBall, 1) }
        addCoins(20)
        normalizeAndSave()
        return true
    }

    var caught: Int { snapshot.caughtCount ?? 0 }

    /// Every wild species ever caught (National Dex ids).
    var caughtSpeciesIDs: Set<Int> { Set(snapshot.caughtSpecies ?? []) }

    /// Puts an Ever Stone in the buddy's paws, or takes it back. Only works
    /// while the bag actually holds one; the stone is never consumed.
    @discardableResult
    func setEvolutionHeld(_ on: Bool) -> Bool {
        if on {
            guard count(of: .everStone) > 0 else { return false }
            snapshot.frozenStage = stage
        } else {
            snapshot.frozenStage = nil
        }
        snapshot.evolutionHeld = on
        save()
        objectWillChange.send()
        return true
    }

    // MARK: - Desktop companion

    var desktopVisible: Bool { snapshot.desktopVisible ?? true }

    func setDesktopVisible(_ visible: Bool) {
        snapshot.desktopVisible = visible
        save()
        objectWillChange.send()
    }

    func desktopPos() -> NSPoint? {
        guard let x = snapshot.posX, let y = snapshot.posY else { return nil }
        return NSPoint(x: x, y: y)
    }

    func setDesktopPos(x: Double, y: Double) {
        snapshot.posX = x
        snapshot.posY = y
        save()
    }

    // MARK: - Simulation

    private func tick() {
        guard snapshot.species != nil else { return }
        let now = Date()
        let dt = now.timeIntervalSince(snapshot.lastTick)
        guard dt > 0 else { return }
        snapshot.lastTick = now
        let beforeLevel = level
        apply(dt: dt)
        snapshot.xp += dt / 60
        if level > beforeLevel {
            let reward = 25 * (level - beforeLevel)
            addCoins(reward)
            NotificationCenter.default.post(
                name: .pokePalToast, object: nil,
                userInfo: ["message": "Level up! +\(reward) coins"]
            )
        }
        if snapshot.sleeping && snapshot.energy >= 100 { snapshot.sleeping = false }
        normalizeAndSave()
    }

    private func applyOfflineDecay() {
        guard snapshot.species != nil else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(snapshot.lastTick)
        guard elapsed > 1 else { return }
        apply(dt: min(elapsed, 86400))
        snapshot.lastTick = now
        normalizeAndSave()
    }

    /// Rates per second of wall time.
    private func apply(dt: TimeInterval) {
        let h = dt / 3600
        if snapshot.sleeping {
            snapshot.energy += 17 * h      // full in ~6h
            snapshot.hunger -= 4 * h
            snapshot.happiness -= 1 * h
        } else {
            snapshot.hunger -= 8 * h       // empty in ~12h
            snapshot.happiness -= 5 * h    // empty in ~20h
            snapshot.energy -= 7 * h       // empty in ~14h
        }
    }

    private func normalizeAndSave() {
        snapshot.hunger = clamp(snapshot.hunger)
        snapshot.happiness = clamp(snapshot.happiness)
        snapshot.energy = clamp(snapshot.energy)
        snapshot.xp = max(0, snapshot.xp)
        save()
        objectWillChange.send()
    }

    private func clamp(_ v: Double) -> Double { min(100, max(0, v)) }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}
