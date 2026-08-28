// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import Foundation
import Combine
import AppKit

extension Notification.Name {
    static let spriteCacheDidUpdate = Notification.Name("PokePal.spriteCacheDidUpdate")
    static let pokePalCelebrate = Notification.Name("PokePal.celebrate")
    static let pokePalToast = Notification.Name("PokePal.toast")
    /// `userInfo["icon"]` carries the fetched app's NSImage.
    static let pokePalFetch = Notification.Name("PokePal.fetch")
}

enum PetMood {
    case great, okay, sad, critical, sleeping, fainted

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
        case .fainted:
            return ["has fainted...", "is out cold...", "collapsed from neglect..."].randomElement()!
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
    /// Spare copies per species (dex id as string, matching inventory's JSON
    /// shape): catching a species again stacks here, and each copy can be
    /// transferred for tier-ranked rewards.
    var duplicates: [String: Int]?
    var inventory: [String: Int]?
    var activeBall: String?
    var coins: Int?
    /// True while the buddy holds an Ever Stone (shop-only item): its stage is
    /// frozen so it stops evolving until the stone is put down.
    var evolutionHeld: Bool?
    /// The stage the buddy was at when the stone was picked up.
    var frozenStage: Int?
    /// When the current nap ends (see `PetNapSchedule`); nil while awake.
    var wakeAt: Date?
    /// When hunger or happiness first bottomed out; nil while both are above
    /// zero. `PetLevelCurve.faintDelay` is counted from here.
    var emptySince: Date?
    /// Set the moment the buddy faints, cleared when it is revived.
    var faintedAt: Date?
    /// Which XP scale `xp` is written on. nil means the old flat
    /// 100-per-level ladder and is converted once on load.
    var curveVersion: Int?
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

        // Saves written before the quadratic curve measured XP on a flat
        // 100-a-level ladder, so reading them straight would drop a fully
        // evolved buddy back to Lv 4 and un-evolve it. Convert once: keep the
        // level and the fraction through it, re-expressed on the new ladder.
        if snapshot.curveVersion == nil {
            let oldLevel = min(PetLevelCurve.maxLevel, Int(snapshot.xp / 100) + 1)
            let oldProgress = snapshot.xp.truncatingRemainder(dividingBy: 100) / 100
            snapshot.xp = PetLevelCurve.totalXP(toReach: oldLevel)
                + PetLevelCurve.levelSpan(at: oldLevel) * oldProgress
            snapshot.curveVersion = 1
            save()
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

    var level: Int { PetLevelCurve.level(for: snapshot.xp) }
    var levelProgress: Double { PetLevelCurve.progress(for: snapshot.xp) }

    /// True while the buddy is down and needs reviving. Nothing but `revive()`
    /// gets it back up: care, naps and encounters are all off the table.
    var isFainted: Bool { snapshot.faintedAt != nil }

    var stage: Int {
        guard let s = species else { return 0 }
        let stageByLevel = level >= PetLevelCurve.finalStageLevel
            ? 2
            : (level >= PetLevelCurve.secondStageLevel ? 1 : 0)
        let natural = min(stageByLevel, s.evoIDs.count - 1)
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
        return stage == 0 ? PetLevelCurve.secondStageLevel : PetLevelCurve.finalStageLevel
    }

    /// Name of the stage the buddy is growing into, nil at the final stage.
    var nextEvolutionName: String? {
        guard let s = species, stage < s.names.count - 1 else { return nil }
        return s.names[stage + 1]
    }

    var mood: PetMood {
        if isFainted { return .fainted }
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

    enum FeedOutcome { case ate, full, noBerries, fainted }

    func feed() -> FeedOutcome {
        guard snapshot.species != nil else { return .noBerries }
        guard !isFainted else { return .fainted }
        if snapshot.sleeping { snapshot.sleeping = false }
        guard snapshot.hunger < 99 else { return .full }
        guard consume(.berry) else { return .noBerries }
        // XP is paid for the hunger the berry actually filled, not for the
        // press: a nearly full buddy eats for almost nothing, so a day's
        // feeding XP is capped by the day's hunger decay.
        snapshot.xp += PetLevelCurve.careXP(restored: min(26, 100 - snapshot.hunger))
        snapshot.hunger += 26
        snapshot.happiness += 4
        maybeFindItem()
        normalizeAndSave()
        return .ate
    }

    @discardableResult
    func play() -> Bool {
        guard snapshot.species != nil, !isFainted else { return false }
        if snapshot.sleeping { snapshot.sleeping = false }
        guard snapshot.energy >= 15 else { return false }
        snapshot.xp += PetLevelCurve.careXP(restored: min(22, 100 - snapshot.happiness))
        snapshot.happiness += 22
        snapshot.energy -= 14
        snapshot.hunger -= 6
        maybeFindItem()
        normalizeAndSave()
        return true
    }

    @discardableResult
    func pet() -> Bool {
        guard snapshot.species != nil, !snapshot.sleeping, !isFainted else { return false }
        // Petting shares one happiness pool with Play, so the two cannot be
        // stacked into free XP — and a maxed-out buddy pays nothing at all.
        snapshot.xp += PetLevelCurve.careXP(restored: min(2.5, 100 - snapshot.happiness))
        snapshot.happiness += 2.5
        maybeFindItem()
        normalizeAndSave()
        return true
    }

    func toggleSleep() {
        // A fainted buddy is not napping: nothing wakes it but a revive, and
        // the desktop tap routes through here too.
        guard snapshot.species != nil, !isFainted else { return }
        snapshot.sleeping.toggle()
        // A pressed sleep is a timed nap: the buddy dozes off and wakes up
        // on its own after a random stretch (or sooner if tapped again).
        snapshot.wakeAt = snapshot.sleeping
            ? Date().addingTimeInterval(PetNapSchedule.wakeDelay())
            : nil
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
        guard snapshot.species != nil, !isFainted else { return false }
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
        guard snapshot.species != nil, !isFainted else { return false }
        // Deliberately no wake here: the throw panel is its own little
        // window, and a buddy that finally nods off shouldn't be jolted
        // awake because the player caught something over on the side.
        snapshot.happiness += 8
        // A catch pays by how hard it was to land, so a legendary stakeout is
        // worth a stack of Caterpies.
        snapshot.xp += speciesID.map { PetCatchTier.tier(for: $0).catchXP } ?? 12
        snapshot.caughtCount = (snapshot.caughtCount ?? 0) + 1
        if let speciesID {
            var caught = snapshot.caughtSpecies ?? []
            if !caught.contains(speciesID) {
                caught.append(speciesID)
                snapshot.caughtSpecies = caught
            } else {
                // Already on the roster: the new copy stacks as a duplicate
                // the player can transfer for rewards on the pet page.
                var dupes = snapshot.duplicates ?? [:]
                dupes["\(speciesID)", default: 0] += 1
                snapshot.duplicates = dupes
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

    /// Spare copies of a species beyond the first catch.
    func duplicateCount(for speciesID: Int) -> Int {
        snapshot.duplicates?["\(speciesID)"] ?? 0
    }

    /// Sends one spare copy away for tier-ranked rewards (a common spare
    /// pays balls and berries; a legendary spare pays an Ultra Ball and
    /// better). Returns the toast line, or nil when there is no spare.
    func transferDuplicate(speciesID: Int) -> String? {
        guard duplicateCount(for: speciesID) > 0 else { return nil }
        var dupes = snapshot.duplicates ?? [:]
        let key = "\(speciesID)"
        dupes[key, default: 1] -= 1
        if dupes[key] == 0 { dupes.removeValue(forKey: key) }
        snapshot.duplicates = dupes

        let tier = PetCatchTier.tier(for: speciesID)
        var parts: [String] = []
        for reward in tier.transferRewards {
            addItem(reward.kind, reward.count)
            parts.append("+\(reward.count)× \(reward.kind.displayName)")
        }
        addCoins(tier.transferCoins)
        parts.append("+\(tier.transferCoins) coins")
        save()
        objectWillChange.send()
        return parts.joined(separator: " · ")
    }

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

    // MARK: - Fainting

    /// Out of energy the buddy drops where it stands. Exhaustion is a nap,
    /// never a faint — a player who forgets to press Sleep shouldn't lose a
    /// level for it, so only hunger and happiness feed the faint clock.
    private func collapseIfExhausted() {
        guard !isFainted, !snapshot.sleeping, snapshot.energy <= 0 else { return }
        snapshot.sleeping = true
        snapshot.wakeAt = nil   // sleeps until rested, not on a nap timer
    }

    /// Hunger or happiness held at zero for `PetLevelCurve.faintDelay` puts
    /// the buddy down: it lies where it is, refuses every kind of care, and
    /// loses a quarter of its current level. Items, coins, dex and catches
    /// all survive — only the climb is set back.
    /// The clock only runs while the app does: a buddy left starving over a
    /// weekend with the mac off comes back on zero stats but on a fresh six
    /// hours, so time away can never kill it before the player can feed it.
    private func faintIfNeglected() {
        guard !isFainted, let since = snapshot.emptySince,
              Date().timeIntervalSince(since) >= PetLevelCurve.faintDelay else { return }

        let before = level
        snapshot.faintedAt = Date()
        // The whole desktop choreography already keys off `sleeping`, so the
        // sprite lies down for free; `toggleSleep` refuses to wake it.
        snapshot.sleeping = true
        snapshot.wakeAt = nil
        snapshot.xp = PetLevelCurve.xpAfterFaint(snapshot.xp)
        save()
        objectWillChange.send()

        let drop = level < before ? " Dropped to Lv \(level)." : ""
        NotificationCenter.default.post(
            name: .pokePalToast, object: nil,
            userInfo: ["message": "\(name) fainted!\(drop) Revive it in the Buddy tab."]
        )
    }

    enum ReviveOutcome { case revived, noPayment, notFainted }

    /// Brings a fainted buddy back on an Oran Berry, or on
    /// `PetLevelCurve.reviveCoins` when the bag is empty. It wakes up at a
    /// third of everything: alive, and still needing a real meal.
    @discardableResult
    func revive() -> ReviveOutcome {
        guard isFainted else { return .notFainted }
        guard consume(.berry) || spendCoins(PetLevelCurve.reviveCoins) else { return .noPayment }
        snapshot.faintedAt = nil
        snapshot.sleeping = false
        snapshot.wakeAt = nil
        snapshot.hunger = max(snapshot.hunger, 35)
        snapshot.happiness = max(snapshot.happiness, 35)
        snapshot.energy = max(snapshot.energy, 35)
        normalizeAndSave()   // clears emptySince now that the stats are back up
        return .revived
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
        // Time alone no longer levels anything: the drip only runs while the
        // buddy is genuinely thriving, which takes feeding and playing.
        if mood == .great { snapshot.xp += dt * PetLevelCurve.bondXPPerSecond }
        if level > beforeLevel {
            let reward = ((beforeLevel + 1)...level).reduce(0) { $0 + PetLevelCurve.levelUpCoins(for: $1) }
            addCoins(reward)
            NotificationCenter.default.post(
                name: .pokePalToast, object: nil,
                userInfo: ["message": "Level up! +\(reward) coins"]
            )
        }
        if !isFainted {
            if PetNapSchedule.shouldWake(sleeping: snapshot.sleeping, wakeAt: snapshot.wakeAt, now: Date()) {
                snapshot.sleeping = false
                snapshot.wakeAt = nil
            }
            if snapshot.sleeping && snapshot.energy >= 100 {
                snapshot.sleeping = false
                snapshot.wakeAt = nil
            }
        }
        collapseIfExhausted()
        normalizeAndSave()
        faintIfNeglected()
    }

    private func applyOfflineDecay() {
        guard snapshot.species != nil else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(snapshot.lastTick)
        guard elapsed > 1 else { return }
        apply(dt: min(elapsed, 86400))
        snapshot.lastTick = now
        collapseIfExhausted()
        normalizeAndSave()
        faintIfNeglected()
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
        // Every mutation lands here, so this is the one place that always sees
        // the final stats: rock bottom starts the faint clock, any care at all
        // clears it.
        if snapshot.hunger <= 0 || snapshot.happiness <= 0 {
            if snapshot.emptySince == nil { snapshot.emptySince = Date() }
        } else {
            snapshot.emptySince = nil
        }
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
