// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

// MARK: - Animated sprite (plays the GIF's own frames)

struct AnimatedSpriteView: View {
    let id: Int
    let height: CGFloat
    var sleeping = false

    @State private var frameIdx = 0
    @State private var refresh = false

    private static let clock = Timer.publish(every: 0.09, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let frames = SpriteCache.frames(for: id), !frames.isEmpty {
                if frames.count > 1 {
                    Image(decorative: frames[min(frameIdx, frames.count - 1)], scale: 2)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: height)
                        .onReceive(Self.clock) { _ in
                            frameIdx = (frameIdx + 1) % frames.count
                        }
                } else {
                    Image(decorative: frames[0], scale: 2)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: height)
                }
            } else {
                VStack(spacing: 4) {
                    ProgressView()
                    Text("fetching...")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .frame(height: height)
            }
        }
        .saturation(sleeping ? 0.45 : 1)
        .brightness(sleeping ? -0.15 : 0)
        .opacity(sleeping ? 0.92 : 1)
        .animation(.easeInOut(duration: 0.3), value: sleeping)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .spriteCacheDidUpdate)) { _ in
            refresh.toggle()
        }
    }
}

// MARK: - Sprite area (panel card)

struct SpriteArea: View {
    @EnvironmentObject private var pet: PetState
    @Binding var hearts: [FloatingHeart]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))

            if let id = pet.dexID {
                AnimatedSpriteView(
                    id: id,
                    height: pet.stage == 2 ? 104 : 92,
                    sleeping: pet.snapshot.sleeping
                )
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }

            if pet.snapshot.sleeping {
                SleepBubble()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 24)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
            }

            heartsLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.35), value: pet.snapshot.sleeping)
    }

    private var heartsLayer: some View {
        ForEach(hearts) { heart in
            FloatingHeartView(heart: heart) {
                hearts.removeAll { $0.id == heart.id }
            }
        }
    }
}

struct FloatingHeart: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
}

struct FloatingHeartView: View {
    let heart: FloatingHeart
    let onDone: () -> Void
    @State private var risen = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: heart.size))
            .foregroundStyle(Color.pink.opacity(0.9))
            .offset(x: heart.x, y: risen ? -48 : 10)
            .opacity(risen ? 0 : 1)
            .scaleEffect(risen ? 1.25 : 0.6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) { risen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { onDone() }
            }
    }
}

// MARK: - Sleep status bubble (classic "Zzz" balloon)

struct SleepBubble: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: -2) {
            Text("Z z")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.indigo)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 6))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.95)))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.indigo.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .scaleEffect(pulse ? 1.07 : 0.97)
        .offset(y: pulse ? -2 : 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.7)))
        .allowsHitTesting(false)
    }
}

// MARK: - Poke ball icon

extension PetItemKind {
    var tint: Color {
        switch self {
        case .pokeBall: return .red
        case .greatBall: return .blue
        case .ultraBall: return .yellow
        case .berry: return .orange
        case .everStone: return .mint
        }
    }

    var price: Int {
        switch self {
        case .pokeBall: return 10
        case .greatBall: return 30
        case .ultraBall: return 80
        case .berry: return 8
        // Shop-only on purpose: the stone is never a random drop, so pausing
        // evolution is always a deliberate purchase.
        case .everStone: return 120
        }
    }
}

struct PokeBallIcon: View {
    let size: CGFloat
    var tint: Color = .red

    var body: some View {
        let lw = max(1.2, size * 0.07)
        return ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(tint)
                Rectangle().fill(Color.white)
            }
            Rectangle().fill(Color.black.opacity(0.85)).frame(height: lw)
            Circle().strokeBorder(Color.black.opacity(0.85), lineWidth: lw)
            Circle().fill(Color.black.opacity(0.85))
                .frame(width: size * 0.26, height: size * 0.26)
            Circle().fill(Color.white)
                .frame(width: size * 0.15, height: size * 0.15)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Bag chips & shop

struct CoinBadge: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circlebadge.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(.yellow)
            Text("\(amount)")
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.yellow.opacity(0.15)))
    }
}

/// Big inventory card. Tapping a ball selects it as the active throw ball.
struct ItemCard: View {
    let kind: PetItemKind
    let count: Int
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                icon
                    .frame(height: 26)
                Text(kind.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(count == 0 ? Color.secondary : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(selected ? kind.tint.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        selected ? AnyShapeStyle(kind.tint) : AnyShapeStyle(Color.clear),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private var icon: some View {
        if kind == .berry {
            Image(systemName: "carrot.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.orange)
        } else if kind == .everStone {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.mint)
        } else {
            PokeBallIcon(size: 24, tint: kind.tint)
        }
    }
}

/// Shop listing row with a buy button.
struct ShopRow: View {
    let kind: PetItemKind
    let price: Int
    let canAfford: Bool
    let onBuy: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if kind == .berry {
                Image(systemName: "carrot.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.orange)
                    .frame(width: 22)
            } else {
                PokeBallIcon(size: 18, tint: kind.tint)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 2) {
                    Image(systemName: "circlebadge.2.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.yellow)
                    Text("\(price)")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onBuy) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(canAfford ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canAfford)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Stat bar

struct StatBar: View {
    let icon: String
    let color: Color
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(value < 20 ? Color.red : color)
                .frame(width: 16)

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(value < 20 ? AnyShapeStyle(Color.red) : AnyShapeStyle(color))
                        .frame(width: max(6, g.size.width * value / 100))
                }
            }
            .frame(height: 9)

            Text("\(Int(value))")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
    }
}

// MARK: - Action button

struct ActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(tint.opacity(0.15))
            )
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(tint)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

// MARK: - Companion panel (buddy care + bag)

struct PetPanel: View {
    var onSwitchBuddy: () -> Void

    @EnvironmentObject private var pet: PetState
    @State private var tab = 0
    @State private var hearts: [FloatingHeart] = []
    @State private var showResetConfirm = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                Text("Buddy").tag(0)
                Text("Bag").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                buddyTab
            } else {
                bagTab
            }

            footer
        }
        .padding(16)
        .overlay {
            if showResetConfirm {
                resetCard
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: showResetConfirm)
        .onReceive(NotificationCenter.default.publisher(for: .pokePalToast)) { note in
            if let message = note.userInfo?["message"] as? String {
                showToast(message)
            }
        }
    }

    // MARK: Buddy tab

    private var buddyTab: some View {
        VStack(spacing: 12) {
            header
            SpriteArea(hearts: $hearts)
                .frame(height: 122)
            moodLine
            stats
            FetchAppsView(onFetched: { name in
                showToast("Fetched \(name)!")
                NotificationCenter.default.post(name: .pokePalCelebrate, object: nil)
            })
            actions
        }
    }

    // MARK: Bag tab

    private var bagTab: some View {
        VStack(spacing: 10) {
            HStack {
                CoinBadge(amount: pet.coinBalance)
                Spacer()
                Text("earn coins by catching & leveling up")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(PetItemKind.allCases, id: \.self) { kind in
                    ItemCard(
                        kind: kind,
                        count: pet.count(of: kind),
                        selected: isSelected(kind)
                    ) {
                        if isBall(kind), pet.count(of: kind) > 0 {
                            pet.setActiveBall(kind)
                            showToast("\(kind.displayName) selected")
                        } else if kind == .berry {
                            useBerry()
                        } else if kind == .everStone {
                            toggleEverStone()
                        }
                    }
                }
            }

            if pet.evolutionBlocked {
                Text("Ever Stone held — evolution paused")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.mint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isBall(pet.activeBall) {
                Text("Active throw ball: \(pet.activeBall.displayName)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            Text("SHOP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(PetItemKind.allCases, id: \.self) { kind in
                    ShopRow(
                        kind: kind,
                        price: kind.price,
                        canAfford: pet.coinBalance >= kind.price
                    ) {
                        buy(kind)
                    }
                }
            }

            Text("Catches drop items · wild ones appear every few minutes")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func isBall(_ kind: PetItemKind) -> Bool {
        kind == .pokeBall || kind == .greatBall || kind == .ultraBall
    }

    private func isSelected(_ kind: PetItemKind) -> Bool {
        if kind == .everStone { return pet.evolutionBlocked }
        return isBall(kind) && pet.activeBall == kind
    }

    /// Hold or put down the Ever Stone. The stone itself is never consumed —
    /// holding it just pauses evolution until it's put back in the bag.
    private func toggleEverStone() {
        if pet.evolutionBlocked {
            _ = pet.setEvolutionHeld(false)
            showToast("Evolution resumed")
        } else if pet.setEvolutionHeld(true) {
            showToast("Evolution paused")
        } else {
            showToast("Buy an Ever Stone in the shop first!")
        }
    }

    private func buy(_ kind: PetItemKind) {
        guard pet.spendCoins(kind.price) else {
            showToast("Not enough coins!")
            return
        }
        pet.addItem(kind)
        showToast("Bought \(kind.displayName)!")
    }

    // MARK: Header / mood / stats

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(
                "Name",
                text: Binding(
                    get: { pet.name },
                    set: { pet.name = String($0.prefix(14)) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .bold, design: .rounded))

            Spacer()

            Text("Lv \(pet.level)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))

            Button {
                onSwitchBuddy()
            } label: {
                Image(systemName: "pawprint")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .help("Switch buddy")

            Button {
                showResetConfirm.toggle()
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(PressableStyle())
            .help("Reset everything")
        }
    }

    private var moodLine: some View {
        HStack(spacing: 4) {
            Image(systemName: moodIcon)
                .foregroundStyle(moodColor)
                .font(.system(size: 11))
            Text("\(pet.name) \(pet.mood.text)")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .id(pet.mood.text)
    }

    private var stats: some View {
        VStack(spacing: 8) {
            StatBar(icon: "fork.knife", color: .orange, value: pet.snapshot.hunger)
            StatBar(icon: "heart.fill", color: .pink, value: pet.snapshot.happiness)
            StatBar(icon: "bolt.fill", color: .yellow, value: pet.snapshot.energy)
            HStack(spacing: 6) {
                Text(evoText)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(Color.purple)
                            .frame(width: max(3, g.size.width * pet.levelProgress))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private var evoText: String {
        if pet.evolutionBlocked { return "Ever Stone stops evolution" }
        guard let next = pet.nextEvolutionLevel else {
            return pet.species?.supportsEvolution == true ? "Final form" : "No evolution"
        }
        if let name = pet.nextEvolutionName {
            return "\(name) at Lv \(next)"
        }
        return "Evolves at Lv \(next)"
    }

    // MARK: Actions

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ActionButton(title: "Feed", icon: "carrot", tint: .orange) {
                useBerry()
            }
            ActionButton(title: "Play", icon: "gamecontroller.fill", tint: .blue) {
                if pet.play() { burst() } else { showToast("Too tired to play...") }
            }
            ActionButton(
                title: pet.snapshot.sleeping ? "Wake" : "Sleep",
                icon: pet.snapshot.sleeping ? "sun.max.fill" : "moon.zzz.fill",
                tint: .indigo
            ) {
                pet.toggleSleep()
            }
            ActionButton(title: "Pet", icon: "hand.raised.fill", tint: .pink) {
                if pet.pet() { burst(count: 2) }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let toast {
                Text(toast)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else {
                Text(stageLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: toast)
    }

    private var stageLabel: String {
        let names = ["Stage 1", "Stage 2", "Final"]
        var label = "\(pet.species?.name(at: pet.stage) ?? "") · \(names[min(pet.stage, 2)])"
        if pet.caught > 0 { label += " · Caught \(pet.caught)" }
        return label
    }

    // MARK: Reset confirmation card

    private var resetCard: some View {
        ZStack {
            Color.primary.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { showResetConfirm = false }

            VStack(spacing: 10) {
                Text("Release \(pet.name)?")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("ALL progress will be lost — XP, items, coins and catches.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button {
                        showResetConfirm = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.primary)

                    Button {
                        showResetConfirm = false
                        pet.reset()
                    } label: {
                        Text("Release")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.2)))
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(20)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    // MARK: Helpers

    private func useBerry() {
        switch pet.feed() {
        case .ate:
            burst(count: 3)
        case .full:
            showToast("\(pet.name) is full!")
        case .noBerries:
            showToast("No berries! Buy some in the Bag tab.")
        }
    }

    private func burst(count: Int = 5) {
        for _ in 0..<count {
            hearts.append(FloatingHeart(x: .random(in: -34...34), size: .random(in: 10...20)))
        }
        NotificationCenter.default.post(name: .pokePalCelebrate, object: nil)
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toast = nil }
        }
    }

    private var moodIcon: String {
        switch pet.mood {
        case .great: return "face.smiling"
        case .okay: return "face.dashed"
        case .sad: return "face.frowning"
        case .critical: return "exclamationmark.triangle.fill"
        case .sleeping: return "zzz"
        }
    }

    private var moodColor: Color {
        switch pet.mood {
        case .great: return .green
        case .okay: return .orange
        case .sad, .critical: return .red
        case .sleeping: return .indigo
        }
    }
}

// MARK: - Buddy chooser (horizontal scroll + search)

struct BuddyChooser: View {
    let initial: Bool
    let onPicked: () -> Void

    /// The classic first-partner Pokémon, one per region. These (plus Dedenne,
    /// the default companion) are selectable from the start; every other
    /// species joins the roster once the player catches it in the wild.
    static let starterDexIDs: Set<Int> = [
        1, 4, 7,            // Kanto
        152, 155, 158,      // Johto
        252, 255, 258,      // Hoenn
        387, 390, 393,      // Sinnoh
        495, 498, 501,      // Unova
        650, 653, 656,      // Kalos
        722, 725, 728,      // Alola (Rowlet, Litten, Popplio)
        810, 813, 816,      // Galar
        906, 909, 912       // Paldea
    ]

    @EnvironmentObject private var pet: PetState
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// Every species the player is currently allowed to pick.
    private var roster: [SpeciesDef] {
        var ids = Self.starterDexIDs
        ids.insert(702) // Dedenne
        ids.formUnion(pet.caughtSpeciesIDs)
        return speciesCatalog.filter { ids.contains($0.baseID) }
    }

    private var filtered: [SpeciesDef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return roster }
        return roster.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(initial ? "Choose your buddy" : "Switch buddy")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .padding(.top, 16)

            Text("Starters are always here — catch a wild Pokémon to unlock it")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search pokemon...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 10) {
                    ForEach(filtered) { def in
                        card(def)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: 148)

            if filtered.isEmpty {
                Text("No pokemon match \"\(query)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }

            if !initial {
                HStack {
                    Button("Back") { onPicked() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Progress carries over when you switch")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            if initial { searchFocused = false }
        }
    }

    private func card(_ def: SpeciesDef) -> some View {
        let isCurrent = pet.species?.key == def.key
        return Button {
            pet.switchTo(def.key)
            onPicked()
        } label: {
            VStack(spacing: 5) {
                AnimatedSpriteView(id: def.baseID, height: 58)
                Text(def.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(def.tagline)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .frame(width: 104, height: 132)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isCurrent ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isCurrent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08)),
                        lineWidth: isCurrent ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Root companion surface (chooser or panel)

struct PetCompanionView: View {
    @EnvironmentObject private var pet: PetState
    @State private var showChooser = false

    var body: some View {
        Group {
            if pet.species == nil || showChooser {
                BuddyChooser(
                    initial: pet.species == nil,
                    onPicked: { withAnimation(.easeInOut(duration: 0.2)) { showChooser = false } }
                )
            } else {
                PetPanel(onSwitchBuddy: {
                    withAnimation(.easeInOut(duration: 0.2)) { showChooser = true }
                })
            }
        }
        // Fills the menu panel's section column and stays a sensible card
        // width on the wider Settings page.
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
    }
}
