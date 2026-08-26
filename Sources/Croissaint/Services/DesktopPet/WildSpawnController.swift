// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

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
            hearts.append(FloatingHeart(x: .random(in: -70...70), size: .random(in: 12...22)))
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

    /// Species-weighted odds: a Poké Ball catches bugs, not Mewtwo.
    func catchOdds(for kind: PetItemKind, dexID: Int?) -> Double {
        guard let dexID else { return 0 }
        return PetCatchTier.tier(for: dexID).odds(for: kind)
    }

    /// Pity threshold for the current wild pokemon.
    func pityMisses(dexID: Int?) -> Int {
        guard let dexID else { return 2 }
        return PetCatchTier.tier(for: dexID).pityMisses
    }

    func noteMiss() {
        misses += 1
        vm.missPulse.toggle()
    }

    func completeCatch(id: Int) {
        let name = wildPool.first { $0.id == id }?.name ?? "Pokémon"
        _ = pet?.catchReward(speciesID: id)
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
        // Generous stage: the whole point of the throw is watching the ball
        // fly, so the arc gets real vertical room.
        let size = NSSize(width: 280, height: 430)
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
    static let gravity: CGFloat = 1500      // downward pull — floaty enough to watch the arc
    static let airDrag: CGFloat = 0.9       // horizontal velocity lost per second
    static let step: CGFloat = 1.0 / 60
    static let minFlickSpeed: CGFloat = 320 // a limp drag just drops back
    static let hitRadius: CGFloat = 56      // half the sprite's width
    static let depthScale: CGFloat = 0.55   // ball size once it reaches the pokemon
    static let maxFlightTime: CGFloat = 4

    // Every throw tumbles: the base roll the ball carries no matter how it
    // was flicked, plus a little extra for faster throws.
    static let baseFlightRoll: CGFloat = 950        // deg/s
    static let rollPerSpeed: CGFloat = 0.35         // extra deg/s per pt/s of launch speed
    static let aimRollPerPoint: CGFloat = 2.2       // deg of roll per point dragged sideways

    // Sidespin (Magnus effect): how much of the flick's lateral speed becomes
    // spin, and how hard that spin bends the flight path. A sideways-flicking
    // throw curves through the air instead of flying straight.
    static let spinFromFlick: CGFloat = 1.1     // deg/s of spin per pt/s of lateral flick
    static let maxSpin: CGFloat = 1500          // deg/s ceiling
    static let curvePerSpin: CGFloat = 0.22     // lateral pt/s² per deg/s of spin
    static let spinDecay: CGFloat = 1.3         // fraction of spin lost per second
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
    /// Sidespin carried by the ball, in deg/s. Positive curves right and rolls
    /// the ball clockwise; it comes from the flick's lateral speed.
    @State private var spinRate: CGFloat = 0
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
        VStack(spacing: 8) {
            // One top slot: WILD! until the catch lands, Gotcha! after —
            // they share the space instead of stacking over the sprite.
            // Pet-world copy is all one pixel font at one size, the same
            // renderer as the notification banner.
            ZStack {
                PixelTextView(text: "WILD!")
                    .opacity(gotcha ? 0 : 1)
                if gotcha {
                    PixelTextView(text: "Gotcha!")
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .frame(height: 38)
            .animation(.easeInOut(duration: 0.18), value: gotcha)

            encounterArea
                .frame(height: 210)
                .background(frameReader { targetRect = $0 })

            ballSelector
                .padding(.horizontal, 16)

            Spacer(minLength: 0)

            dockedBall
                .frame(height: 76)
                .background(frameReader { dockRect = $0 })

            Text("flick up to throw")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.5))
                .padding(.bottom, 8)
        }
        .padding(.top, 12)
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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primary.opacity(0.06))

            if let id = vm.dexID {
                AnimatedSpriteView(id: id, height: 128)
                    .scaleEffect(spriteGone ? 0.05 : 1)
                    .opacity(spriteGone ? 0 : 1)
                    .scaleEffect(vm.missPulse ? 0.86 : 1)
                    .rotationEffect(.degrees(vm.missPulse ? -7 : 0))
                    .animation(.spring(response: 0.16, dampingFraction: 0.4), value: vm.missPulse)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: spriteGone)
            }

            if let message {
                PixelTextView(text: message)
                    .transition(.opacity)
                    .offset(y: 72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.18), value: gotcha)
    }

    private var ballSelector: some View {
        HStack(spacing: 10) {
            ForEach([PetItemKind.pokeBall, PetItemKind.greatBall, PetItemKind.ultraBall], id: \.self) { kind in
                Button {
                    guard phase == .ready else { return }
                    if controller.ballCount(for: kind) > 0 { pet.setActiveBall(kind) }
                }                 label: {
                    VStack(spacing: 3) {
                        PokeBallIcon(size: 22, tint: kind.tint)
                        Text("\(controller.ballCount(for: kind))")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.black.opacity(0.55))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
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
        PokeBallIcon(size: 48, tint: pet.activeBall.tint)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
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
                // Dragging the ball around in your hand rolls it too (read
                // the previous point before sampleVelocity overwrites it).
                let rollDelta = value.translation.width - lastPoint.width
                sampleVelocity(value.translation)
                ballSpin += Double(rollDelta * ThrowPhysics.aimRollPerPoint)
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
        // A sideways component of the flick puts sidespin on the ball, which
        // bends the arc — pure vertical flicks still fly straight.
        spinRate = min(max(vel.dx * ThrowPhysics.spinFromFlick,
                           -ThrowPhysics.maxSpin),
                       ThrowPhysics.maxSpin)
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

    /// One fixed physics step: gravity, air drag, Magnus curve from the
    /// sidespin, then a check for whether the ball just crossed the pokemon's
    /// plane close enough to hit.
    private func stepFlight(kind: PetItemKind) {
        let dt = ThrowPhysics.step
        let previous = ballPos

        // Spin decays with the air it grips, and bends the flight sideways.
        spinRate *= (1 - ThrowPhysics.spinDecay * dt)
        ballVel.dy += ThrowPhysics.gravity * dt
        ballVel.dx *= (1 - ThrowPhysics.airDrag * dt)
        ballVel.dx += ThrowPhysics.curvePerSpin * spinRate * dt

        let dx = ballVel.dx * dt
        let dy = ballVel.dy * dt
        ballPos.width += dx
        ballPos.height += dy
        // Visible tumble: a steady roll every throw gets, plus the live
        // sidespin contribution while it lasts.
        ballSpin += Double((ThrowPhysics.baseFlightRoll
            + ballVel.length * ThrowPhysics.rollPerSpeed) * dt)
            + Double(spinRate * dt)
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
            || ballPos.height > 90 {
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
        let guaranteed = controller.missCount >= controller.pityMisses(dexID: vm.dexID)
        if Double.random(in: 0..<1) < controller.catchOdds(for: kind, dexID: vm.dexID)
            || guaranteed {
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
            spinRate = 0
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
