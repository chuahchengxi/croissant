// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

// MARK: - Wild species pool

/// Any species in the dex can show up in the wild. Sprites are fetched on
/// demand, so the full pool costs nothing until one actually spawns.
let wildPool: [(id: Int, name: String)] = speciesCatalog.map { (id: $0.baseID, name: $0.name) }

// MARK: - View model

final class WildViewModel: ObservableObject {
    @Published var dexID: Int?
    @Published var missPulse = false
    @Published var hearts: [FloatingHeart] = []

    func spawnHearts(_ count: Int) {
        for _ in 0..<count {
            hearts.append(FloatingHeart(x: .random(in: -40...40), size: .random(in: 10...18)))
        }
    }
}

// MARK: - Controller

final class WildSpawnController {
    static let shared = WildSpawnController()

    private weak var pet: PetState?
    private var panel: NSPanel?
    let vm = WildViewModel()

    private var spawnTimer: Timer?
    private var lifeTimer: Timer?
    private var despawnDeadline = Date.distantPast
    private var misses = 0

    /// Number of failed throws for the current encounter (3rd throw always succeeds).
    var missCount: Int { misses }

    /// Set while a throw sequence is in progress so the pokemon doesn't flee mid-animation.
    var interactionLock = false

    func start(pet: PetState) {
        guard spawnTimer == nil else { return }
        self.pet = pet
        schedule(after: Double.random(in: 45...120))
    }

    /// Cancels every encounter timer and takes the encounter panel down, so a
    /// disabled feature leaves nothing running.
    func stop() {
        spawnTimer?.invalidate()
        spawnTimer = nil
        hide()
    }

    // MARK: Ball API used by the throw UI

    func ballCount(for kind: PetItemKind) -> Int {
        pet?.count(of: kind) ?? 0
    }

    @discardableResult
    func takeBall(_ kind: PetItemKind) -> Bool {
        pet?.consume(kind) ?? false
    }

    func catchOdds(for kind: PetItemKind) -> Double {
        switch kind {
        case .pokeBall: return 0.55
        case .greatBall: return 0.78
        case .ultraBall: return 0.92
        default: return 0
        }
    }

    func noteMiss() {
        misses += 1
        vm.missPulse.toggle()
    }

    func completeCatch(id: Int) {
        let name = wildPool.first { $0.id == id }?.name ?? "Pokémon"
        _ = pet?.catchReward()
        vm.spawnHearts(6)
        NotificationCenter.default.post(name: .pokePalCelebrate, object: nil)
        NotificationCenter.default.post(
            name: .pokePalToast, object: nil,
            userInfo: ["message": "You caught \(name)!"]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self != nil else { return }
            NotificationCenter.default.post(
                name: .pokePalToast, object: nil,
                userInfo: ["message": "+2 Poké Balls · +1 Oran Berry"]
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) { [weak self] in
            self?.hide()
            self?.scheduleNext()
        }
    }

    // MARK: Lifecycle

    private func schedule(after delay: TimeInterval) {
        spawnTimer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.spawn() }
        RunLoop.main.add(t, forMode: .common)
        spawnTimer = t
    }

    private func spawn() {
        // No encounters until a buddy has been chosen.
        guard let pet, pet.snapshot.species != nil else {
            scheduleNext()
            return
        }
        vm.dexID = wildPool.randomElement()!.id
        misses = 0

        setupPanelIfNeeded()
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)

        despawnDeadline = Date().addingTimeInterval(20)
        lifeTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.checkLife() }
        RunLoop.main.add(t, forMode: .common)
        lifeTimer = t
    }

    private func scheduleNext() {
        guard petDesktopWanted() else { return }
        schedule(after: Double.random(in: 180...420))
    }

    private func checkLife() {
        if interactionLock {
            // Keep it around while the player is mid-throw.
            despawnDeadline = max(despawnDeadline, Date().addingTimeInterval(2))
            return
        }
        if Date() > despawnDeadline { flee() }
    }

    private func flee() {
        hide()
        scheduleNext()
    }

    private func hide() {
        interactionLock = false
        panel?.orderOut(nil)
        lifeTimer?.invalidate()
        lifeTimer = nil
    }

    private func setupPanelIfNeeded() {
        guard panel == nil else { return }
        let size = NSSize(width: 190, height: 260)
        let p = FloatingPanel.make(size: size)

        // Plain container: SwiftUI gestures receive events directly,
        // transparent areas fall through to the desktop.
        p.contentView = NSView(frame: NSRect(origin: .zero, size: size))

        let root = WildPokemonView(controller: self)
            .environmentObject(vm)
            .environmentObject(PetState.shared)
        let host = NSHostingView(rootView: root)
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView!.addSubview(host)
        panel = p
    }

    private func positionPanel() {
        guard let panel, let vis = NSScreen.main?.visibleFrame else { return }
        let w = panel.frame.width, h = panel.frame.height
        let minX = vis.minX + 30
        let maxX = vis.maxX - w - 30
        let minY = vis.minY + 40
        let maxY = vis.maxY - h - 110
        guard maxX > minX, maxY > minY else { return }
        panel.setFrameOrigin(
            NSPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        )
    }
}

// MARK: - Throw view (Pokemon GO style)

/// Tuning knobs for the throw arc, in panel points and points/second with y
/// negative upward. Sim runs at a fixed step so the feel doesn't change with
/// frame rate.
private enum ThrowPhysics {
    static let gravity: CGFloat = 1700      // downward pull
    static let airDrag: CGFloat = 0.9       // horizontal velocity lost per second
    static let step: CGFloat = 1.0 / 60
    static let minFlickSpeed: CGFloat = 260 // a limp drag just drops back
    static let hitRadius: CGFloat = 34      // half the sprite's width
    static let depthScale: CGFloat = 0.55   // ball size once it reaches the pokemon
    static let spinPerPoint: Double = 1.1   // degrees of roll per point travelled
    static let maxFlightTime: CGFloat = 3
}

private struct Vec {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }
}

struct WildPokemonView: View {
    let controller: WildSpawnController
    @EnvironmentObject private var vm: WildViewModel
    @EnvironmentObject private var pet: PetState

    private enum Phase { case ready, flying, resolving }
    @State private var phase: Phase = .ready

    // Ball body: position is an offset from its docked spot.
    @State private var ballPos: CGSize = .zero
    @State private var ballVel = Vec()
    @State private var ballSpin: Double = 0
    @State private var flight: Timer?
    @State private var flightTime: CGFloat = 0

    // Flick speed, measured from the drag itself: predictedEndTranslation is
    // inertia-based and stays ~0 for a plain mouse drag.
    @State private var dragVel = Vec()
    @State private var lastPoint: CGSize = .zero
    @State private var lastTime = Date.distantPast

    @State private var wobbleAngle: Double = 0
    @State private var ballVisible = true

    @State private var spriteGone = false
    @State private var gotcha = false
    @State private var message: String?

    // Measured so the aim stays honest if the layout changes.
    @State private var targetRect: CGRect = .zero
    @State private var dockRect: CGRect = .zero

    /// Where the pokemon sits relative to the ball's resting spot.
    private var targetOffset: CGSize {
        CGSize(
            width: targetRect.midX - dockRect.midX,
            height: targetRect.midY - dockRect.midY
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("WILD!")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.yellow.opacity(0.95)))
                .foregroundStyle(Color.black.opacity(0.7))

            encounterArea
                .frame(height: 104)
                .background(frameReader { targetRect = $0 })

            ballSelector
                .padding(.horizontal, 12)

            Spacer(minLength: 0)

            dockedBall
                .frame(height: 56)
                .background(frameReader { dockRect = $0 })

            Text("flick up to throw")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.5))
                .padding(.bottom, 6)
        }
        .padding(.top, 10)
        .coordinateSpace(name: "wild")
        .overlay {
            ForEach(vm.hearts) { heart in
                FloatingHeartView(heart: heart) {
                    vm.hearts.removeAll { $0.id == heart.id }
                }
            }
        }
        .onDisappear { stopFlight() }
    }

    private func frameReader(_ assign: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { g in
            Color.clear.onAppear { assign(g.frame(in: .named("wild"))) }
        }
    }

    // MARK: Sections

    private var encounterArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.06))

            if let id = vm.dexID {
                AnimatedSpriteView(id: id, height: 88)
                    .scaleEffect(spriteGone ? 0.05 : 1)
                    .opacity(spriteGone ? 0 : 1)
                    .scaleEffect(vm.missPulse ? 0.86 : 1)
                    .rotationEffect(.degrees(vm.missPulse ? -7 : 0))
                    .animation(.spring(response: 0.16, dampingFraction: 0.4), value: vm.missPulse)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: spriteGone)
            }

            if gotcha {
                Text("Gotcha!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.yellow.opacity(0.95)))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }

            if let message {
                Text(message)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.85)))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .transition(.opacity)
                    .offset(y: 38)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeInOut(duration: 0.18), value: gotcha)
    }

    private var ballSelector: some View {
        HStack(spacing: 10) {
            ForEach([PetItemKind.pokeBall, PetItemKind.greatBall, PetItemKind.ultraBall], id: \.self) { kind in
                Button {
                    guard phase == .ready else { return }
                    if controller.ballCount(for: kind) > 0 { pet.setActiveBall(kind) }
                } label: {
                    VStack(spacing: 2) {
                        PokeBallIcon(size: 17, tint: kind.tint)
                        Text("\(controller.ballCount(for: kind))")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            pet.activeBall == kind ? Color.white.opacity(0.8) : Color.white.opacity(0.35)
                        )
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            pet.activeBall == kind ? AnyShapeStyle(Color.black.opacity(0.55)) : AnyShapeStyle(Color.clear),
                            lineWidth: 1.2
                        )
                    )
                    .opacity(controller.ballCount(for: kind) == 0 ? 0.35 : 1)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// How small the ball looks at its current depth, i.e. how far along the
    /// line from the dock to the pokemon it has travelled.
    private var depthScale: CGFloat {
        let span = targetOffset.height
        guard span < 0 else { return 1 }
        let t = min(1, max(0, ballPos.height / span))
        return 1 - (1 - ThrowPhysics.depthScale) * t
    }

    /// The throwable ball at the bottom.
    private var dockedBall: some View {
        PokeBallIcon(size: 36, tint: pet.activeBall.tint)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            .rotationEffect(.degrees(ballSpin))
            .rotationEffect(.degrees(wobbleAngle))
            .scaleEffect(depthScale)
            .offset(x: ballPos.width, y: ballPos.height)
            .opacity(ballVisible ? 1 : 0)
            .gesture(throwGesture)
    }

    private var throwGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("wild"))
            .onChanged { value in
                guard phase == .ready else { return }
                sampleVelocity(value.translation)
                ballPos = value.translation
            }
            .onEnded { value in handleRelease(value) }
    }

    // MARK: Throw logic

    /// Smoothed pointer velocity over the last couple of drag events.
    private func sampleVelocity(_ point: CGSize) {
        let now = Date()
        let dt = CGFloat(now.timeIntervalSince(lastTime))
        if dt > 0.001, dt < 0.1 {
            let instant = Vec(dx: (point.width - lastPoint.width) / dt,
                              dy: (point.height - lastPoint.height) / dt)
            dragVel = Vec(dx: (dragVel.dx + instant.dx) / 2, dy: (dragVel.dy + instant.dy) / 2)
        } else if dt >= 0.1 {
            dragVel = Vec()   // the pointer stalled; a resumed drag starts fresh
        }
        lastPoint = point
        lastTime = now
    }

    private func handleRelease(_ value: DragGesture.Value) {
        guard phase == .ready else { return }

        var vel = dragVel
        if vel.length < 1 {
            // No usable samples (a one-event drag): fall back to SwiftUI's
            // inertial projection, spread over the 0.35s window it models.
            vel = Vec(
                dx: (value.predictedEndTranslation.width - value.translation.width) / 0.35,
                dy: (value.predictedEndTranslation.height - value.translation.height) / 0.35
            )
        }

        guard vel.dy < 0, vel.length >= ThrowPhysics.minFlickSpeed else {
            springBack()
            return
        }

        let kind = pet.activeBall
        guard controller.takeBall(kind) else {
            flash("No \(kind.displayName)s left!")
            springBack()
            return
        }

        phase = .flying
        controller.interactionLock = true
        ballPos = value.translation
        ballVel = vel
        flightTime = 0
        startFlight(kind: kind)
    }

    private func startFlight(kind: PetItemKind) {
        stopFlight()
        let t = Timer(timeInterval: TimeInterval(ThrowPhysics.step), repeats: true) { _ in
            stepFlight(kind: kind)
        }
        RunLoop.main.add(t, forMode: .common)
        flight = t
    }

    private func stopFlight() {
        flight?.invalidate()
        flight = nil
    }

    /// One fixed physics step: gravity, a little air drag, then a check for
    /// whether the ball just crossed the pokemon's plane close enough to hit.
    private func stepFlight(kind: PetItemKind) {
        let dt = ThrowPhysics.step
        let previous = ballPos

        ballVel.dy += ThrowPhysics.gravity * dt
        ballVel.dx *= (1 - ThrowPhysics.airDrag * dt)

        let dx = ballVel.dx * dt
        let dy = ballVel.dy * dt
        ballPos.width += dx
        ballPos.height += dy
        ballSpin += Double((dx * dx + dy * dy).squareRoot()) * ThrowPhysics.spinPerPoint
        flightTime += dt

        let target = targetOffset
        // Crossing the pokemon's depth on the way up is the only way to land a hit.
        if previous.height > target.height, ballPos.height <= target.height {
            stopFlight()
            // Interpolate to the exact crossing point so aim doesn't depend on
            // where the frame boundary happened to fall.
            let span = previous.height - ballPos.height
            let t = span > 0 ? (previous.height - target.height) / span : 1
            let crossX = previous.width + (ballPos.width - previous.width) * t
            if abs(crossX - target.width) <= ThrowPhysics.hitRadius {
                ballPos = target
                resolveThrow(with: kind)
            } else {
                missedEntirely()
            }
            return
        }

        // Sailed off the panel, dropped back past the dock, or ran out of time.
        if flightTime > ThrowPhysics.maxFlightTime
            || abs(ballPos.width) > dockRect.width / 2
            || ballPos.height > 60 {
            stopFlight()
            missedEntirely()
        }
    }

    /// The ball never reached the pokemon — no capture roll, but the throw
    /// still counts so a run of bad aim can't stall the encounter forever.
    private func missedEntirely() {
        phase = .resolving
        controller.noteMiss()
        withAnimation(.easeOut(duration: 0.12)) { ballVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            resetBall()
            flash("Missed!")
        }
    }

    private func resolveThrow(with kind: PetItemKind) {
        let guaranteed = controller.missCount >= 2
        if Double.random(in: 0..<1) < controller.catchOdds(for: kind) || guaranteed {
            succeed(with: kind)
        } else {
            controller.noteMiss()
            fail()
        }
    }

    private func succeed(with kind: PetItemKind) {
        phase = .resolving
        // Pokemon gets pulled into the ball.
        withAnimation(.easeIn(duration: 0.15)) { spriteGone = true }

        // Wobble... wobble... click!
        let steps: [(Double, Double)] = [(0.15, 24), (0.45, -18), (0.75, 11), (1.05, 0)]
        for (delay, angle) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.4)) {
                    wobbleAngle = angle
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { gotcha = true }
            vm.spawnHearts(6)
            NotificationCenter.default.post(name: .pokePalCelebrate, object: nil)
            if let id = vm.dexID {
                controller.completeCatch(id: id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { resetAll() }
        }
    }

    private func fail() {
        phase = .resolving
        // Ball bursts away; pokemon shakes angrily.
        withAnimation(.easeOut(duration: 0.12)) { ballVisible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            resetBall()
            flash("It broke free!")
        }
    }

    // MARK: Helpers

    private func springBack() {
        dragVel = Vec()
        lastTime = .distantPast
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
            ballPos = .zero
        }
    }

    private func resetBall() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            ballPos = .zero
            ballVel = Vec()
            dragVel = Vec()
            lastTime = .distantPast
            ballSpin = 0
            wobbleAngle = 0
            ballVisible = true
        }
        phase = .ready
        controller.interactionLock = false
    }

    private func resetAll() {
        resetBall()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            spriteGone = false
            gotcha = false
        }
    }

    private func flash(_ text: String) {
        withAnimation { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { message = nil }
        }
    }
}
