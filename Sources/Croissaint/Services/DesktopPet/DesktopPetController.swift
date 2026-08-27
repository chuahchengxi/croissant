// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
import Combine
import SwiftUI

// MARK: - Reusable floating panel factory

enum FloatingPanel {
    static func make(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        return panel
    }
}

/// Transparent interaction layer: forwards clicks, blocks SwiftUI hit-testing underneath.
final class TapOnlyContainerView: NSView {
    var onTap: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseUp(with event: NSEvent) { onTap?() }
}

// MARK: - View model shared with SwiftUI

final class DesktopViewModel: ObservableObject {
    @Published var facingLeft = true
    @Published var walking = false
    /// Mirrors whether the desktop panel is on screen; views freeze every
    /// timeline while it is hidden so an invisible buddy costs no redraws.
    @Published var buddyVisible = false
    @Published var hearts: [FloatingHeart] = []
    @Published var zzzs: [FloatingZzz] = []
    /// Puff counter for the sleep loop — decides which z's become dreams.
    var zzzCount = 0
    @Published var moves: [PetMoveInstance] = []
    @Published var fetched: [FloatingFetch] = []
    @Published var dizzyStars: [FloatingDizzy] = []
    @Published var notice: PetNotice?
    /// Live while the buddy is mid-throw: the accumulated tumble angle the
    /// sprite spins through, updated per physics step.
    @Published var throwTumble: Double = 0
    /// True from launch until the buddy settles, so views know to animate
    /// flight instead of walk cycles.
    @Published var thrown = false {
        didSet { if !thrown { throwTumble = 0 } }
    }
    /// Bumped on every floor bounce; views play a landing squash per bump.
    @Published var impactCount = 0
    /// Bumped whenever a real system notification reaches the buddy, so the
    /// it reacts (startled hop) instead of just growing a banner.
    @Published var alertPulse = 0
    /// Bumped per petting tap; the view answers with a `PetTapReaction`.
    @Published var petPulse = 0

    func spawnHearts(_ count: Int) {
        for _ in 0..<count {
            hearts.append(FloatingHeart(x: .random(in: -40...40), size: .random(in: 10...18)))
        }
    }

    /// The buddy plays its signature (or type-flavoured) move: a short pixel
    /// particle burst fired in the direction it is facing.
    func spawnMove(pet: PetState) {
        guard let dexID = pet.dexID else { return }
        let move = PetMoveCatalog.move(for: dexID, types: pet.species?.tagline)
        moves.append(PetMoveInstance(style: move.style, facingLeft: facingLeft))
        if moves.count > 2 { moves.removeFirst(moves.count - 2) }
    }

    /// Replaces any visible banner; auto-dismisses unless a newer one lands.
    /// System notifications (not in-app toasts) also startle the buddy —
    /// the hop + popped app icon are what tie the notice to the pokemon.
    func showNotice(text: String, icon: NSImage?, startles: Bool = false) {
        let notice = PetNotice(text: PetPixelArt.text(text), icon: icon.flatMap(PetPixelArt.icon))
        withAnimation(.easeOut(duration: 0.25)) {
            self.notice = notice
        }
        if startles {
            alertPulse += 1
            spawnFetch(icon: icon)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) {
                if self?.notice?.id == notice.id { self?.notice = nil }
            }
        }
    }

    /// A sleepy "z" drifting off the buddy. Old ones are trimmed so a long
    /// nap never accumulates views.
    /// A sleepy "z" drifting off the buddy; every few puffs is a dream
    /// bubble instead, so long naps don't repeat one flat animation. Old
    /// ones are trimmed so a nap never accumulates views.
    func spawnZzz(seed: Int) {
        zzzCount += 1
        let dreaming = zzzCount % max(2, PetSleepChoreography.dreamEvery(seed: seed)) == 0
        zzzs.append(FloatingZzz(
            x: .random(in: 24...46),
            size: .random(in: 9...14),
            dream: dreaming,
            symbol: PetSleepChoreography.dreamSymbol(seed: seed, cycle: zzzCount)
        ))
        if zzzs.count > 5 { zzzs.removeFirst(zzzs.count - 5) }
    }

    /// The buddy proudly presents the app it just fetched: the icon pops out
    /// pixelated and drifts up beside it.
    func spawnFetch(icon: NSImage?) {
        fetched.append(FloatingFetch(icon: icon.flatMap(PetPixelArt.icon), x: .random(in: (-46)...(-24))))
        if fetched.count > 3 { fetched.removeFirst(fetched.count - 3) }
    }

    /// Post-landing dizzy stars for a rough touchdown.
    func spawnDizzy() {
        let star = FloatingDizzy(x: .random(in: -14...14), size: .random(in: 9...13))
        dizzyStars.append(star)
        if dizzyStars.count > 4 { dizzyStars.removeFirst(dizzyStars.count - 4) }
    }
}

/// One drifting "z" puff while the buddy naps.
/// One drifting "z" puff while the buddy naps — or, every few puffs, a
/// dream bubble showing what the buddy is dreaming about.
struct FloatingZzz: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    var dream = false
    var symbol = "z"
}

/// The pixelated app icon the buddy "retrieved" — floats up and fades.
struct FloatingFetch: Identifiable {
    let id = UUID()
    /// Already pixelated (tiny bitmap, nearest-neighbour upscale).
    let icon: CGImage?
    let x: CGFloat
}

struct FloatingFetchView: View {
    let fetch: FloatingFetch
    let onDone: () -> Void
    @State private var risen = false

    var body: some View {
        Group {
            if let icon = fetch.icon {
                Image(decorative: icon, scale: 2)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
        .offset(x: fetch.x + (risen ? 6 : 0), y: risen ? -58 : 8)
        .opacity(risen ? 0 : 1)
        .scaleEffect(risen ? 1.15 : 0.4)
        .onAppear {
            withAnimation(.easeOut(duration: 1.5)) { risen = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { onDone() }
        }
    }
}

/// A dizzy star circling the buddy's head after a hard landing.
struct FloatingDizzy: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
}

struct FloatingDizzyView: View {
    let star: FloatingDizzy
    let onDone: () -> Void
    @State private var spin = false
    @State private var faded = false

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: star.size))
            .foregroundStyle(.yellow.opacity(0.9))
            .shadow(color: .black.opacity(0.2), radius: 1)
            .offset(x: star.x + (spin ? -star.x * 2 : 0), y: -14)
            .rotationEffect(.degrees(spin ? 260 : -60))
            .opacity(faded ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    spin = true
                }
                withAnimation(.easeIn(duration: 0.4).delay(1.0)) {
                    faded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) { onDone() }
            }
    }
}

struct FloatingZzzView: View {
    let zzz: FloatingZzz
    let onDone: () -> Void
    @State private var risen = false

    var body: some View {
        Group {
            if zzz.dream {
                Text(zzz.symbol)
                    .font(.system(size: zzz.size + 3, weight: .black))
                    .foregroundStyle(.pink.opacity(0.85))
                    .shadow(color: .purple.opacity(0.35), radius: 2)
            } else {
                Text("z")
                    .font(.system(size: zzz.size, weight: .black, design: .rounded))
                    .foregroundStyle(.indigo.opacity(0.85))
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.white.opacity(0.75)))
            }
        }
        .offset(x: zzz.x + (risen ? (zzz.dream ? 12 : 8) : 0), y: risen ? (zzz.dream ? -66 : -52) : 6)
        .opacity(risen ? 0 : 0.95)
        .scaleEffect(risen ? 1.15 : 0.7)
        .onAppear {
            withAnimation(.easeOut(duration: zzz.dream ? 2.1 : 1.6)) { risen = true }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (zzz.dream ? 2.15 : 1.65)
            ) { onDone() }
        }
    }
}

/// Whether the buddy may walk the screen right now: the feature must be
/// installed AND its show-on-desktop switch on.
func petDesktopWanted() -> Bool {
    AppFeature.desktopPet.isAvailable
        && UserDefaults.standard.bool(forKey: DefaultsKey.desktopPetEnabled)
}

// MARK: - Controller (window + wander AI)

final class DesktopPetController {
    static let shared = DesktopPetController()

    private var window: NSPanel?
    private weak var pet: PetState?
    let vm = DesktopViewModel()

    private var timer: Timer?
    private var celebrateToken: NSObjectProtocol?
    private var fetchToken: NSObjectProtocol?
    private var noticePanel: PetNoticePanel?
    private var noticeCancellable: AnyCancellable?
    private var walking = false
    private var dir = 1
    private var remaining: TimeInterval = 1.5
    private var isDragging = false
    private var pos = CGPoint.zero
    private var boundsRect = CGRect.zero
    private var isShown = false
    private var lastSleeping = false
    private var nextZzzAt = Date.distantPast
    private var lastTickAt = Date()
    /// Trailing drag samples for the release flick that starts a throw.
    private var dragSamples: [(time: Date, point: CGPoint)] = []
    /// Live throw physics; nil while the buddy is standing on the ground.
    private var flightState: DesktopThrowSupport.State?
    private var flightTimer: Timer?
    private var flightLastStepAt = Date()
    private var flightAccumulator: TimeInterval = 0
    /// Origin last pushed to the window server; skips redundant frame moves.
    private var appliedOrigin: NSPoint?
    private static let speed: CGFloat = 60 // px/s

    func start(pet: PetState) {
        guard timer == nil else { return }
        self.pet = pet
        computeBounds()
        setupWindow()
        PetNotificationBridge.shared.start(vm: vm)
        noticePanel = PetNoticePanel(petWindow: window)
        noticeCancellable = vm.$notice.sink { [weak self] notice in
            guard let self else { return }
            if let notice {
                self.noticePanel?.show(notice: notice)
            } else {
                self.noticePanel?.hide()
            }
        }

        if let saved = pet.desktopPos() {
            pos = CGPoint(x: CGFloat(saved.x), y: CGFloat(saved.y))
        } else if let screen = NSScreen.main?.visibleFrame {
            pos = CGPoint(x: screen.midX - 85, y: screen.minY + 12)
        }
        clampPos()
        appliedOrigin = nil
        applyFrame()

        lastTickAt = Date()
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            // Measure real elapsed time so motion speed stays true when a
            // tick lands late under load.
            let dt = min(0.25, now.timeIntervalSince(self.lastTickAt))
            self.lastTickAt = now
            self.tick(dt)
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t

        celebrateToken = NotificationCenter.default.addObserver(
            forName: .pokePalCelebrate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.vm.spawnHearts(4)
            if let pet = self?.pet {
                self?.vm.spawnMove(pet: pet)
            }
        }

        fetchToken = NotificationCenter.default.addObserver(
            forName: .pokePalFetch, object: nil, queue: .main
        ) { [weak self] notification in
            let icon = notification.userInfo?["icon"] as? NSImage
            self?.vm.spawnFetch(icon: icon)
        }
    }

    /// Tears the walker down: stops ticking and takes the window off screen,
    /// so a disabled feature leaves nothing on the display or in the CPU.
    func stop() {
        timer?.invalidate()
        timer = nil
        cancelFlight()
        PetNotificationBridge.shared.stop()
        noticeCancellable?.cancel()
        noticeCancellable = nil
        noticePanel?.stop()
        noticePanel = nil
        if let celebrateToken {
            NotificationCenter.default.removeObserver(celebrateToken)
            self.celebrateToken = nil
        }
        if let fetchToken {
            NotificationCenter.default.removeObserver(fetchToken)
            self.fetchToken = nil
        }
        window?.orderOut(nil)
        isShown = false
        vm.buddyVisible = false
    }

    /// Only visible when enabled AND a buddy actually exists.
    private func updateVisibility() {
        guard let pet else { return }
        let want = petDesktopWanted()
            && pet.desktopVisible
            && pet.snapshot.species != nil
        if want && !isShown {
            window?.makeKeyAndOrderFront(nil)
            isShown = true
        } else if !want && isShown {
            window?.orderOut(nil)
            isShown = false
        }
        if vm.buddyVisible != (want && pet.snapshot.species != nil) {
            vm.buddyVisible = want && pet.snapshot.species != nil
        }
    }

    func setVisible(_ visible: Bool) {
        if visible { window?.makeKeyAndOrderFront(nil) }
        else { window?.orderOut(nil) }
        isShown = window?.isVisible ?? false
        vm.buddyVisible = isShown
    }

    private func setupWindow() {
        guard window == nil else { return }
        let size = NSSize(width: 170, height: 170)
        let panel = FloatingPanel.make(size: size)

        let container = DesktopContainerView(frame: NSRect(origin: .zero, size: size), controller: self)
        panel.contentView = container

        let root = DesktopPetView()
            .environmentObject(vm)
            .environmentObject(PetState.shared)
        let host = PetPassThroughHostingView(rootView: root)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        window = panel
    }

    private func computeBounds() {
        boundsRect = (NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900))
            .insetBy(dx: 16, dy: 8)
    }

    private func tick(_ dt: TimeInterval) {
        guard let pet else { return }
        updateVisibility()

        guard window?.isVisible == true, !isDragging, pet.snapshot.species != nil else { return }

        // Mid-flight the physics timer owns the body: no wander AI, no nap
        // gliding — just the arc.
        if flightState != nil { return }

        // React to sleep/wake transitions.
        let sleeping = pet.snapshot.sleeping
        if sleeping != lastSleeping {
            lastSleeping = sleeping
            walking = false
            if vm.walking { vm.walking = false }
            remaining = sleeping ? .greatestFiniteMagnitude : Double.random(in: 1...2.5)
        }

        // While sleeping, drift to the nearest screen corner and nap there.
        if sleeping {
            glideToNearestCorner(dt)
            // Snore on a beat: a drifting z every couple of seconds, with
            // dream bubbles surfacing every few puffs.
            // Custom sprites have no dex id; they snore on seed 0 like the
            // pose choreography does.
            if Date() >= nextZzzAt {
                vm.spawnZzz(seed: pet.dexID ?? 0)
                nextZzzAt = Date().addingTimeInterval(Double.random(in: 1.7...2.5))
            }
            return
        }

        remaining -= dt
        if remaining <= 0 {
            walking.toggle()
            if walking {
                dir = [-1, 1].randomElement() ?? 1
                remaining = Double.random(in: 1.5...4.5)
            } else {
                remaining = Double.random(in: 1.5...4)
            }
        }

        let moving = walking && !pet.snapshot.sleeping
        if vm.walking != moving { vm.walking = moving }
        // Facing only tracks the walk while actually walking, so a buddy
        // that stops keeps standing the way it last headed.
        if moving {
            if vm.facingLeft != (dir == -1) { vm.facingLeft = dir == -1 }
            pos.x += CGFloat(dir) * Self.speed * CGFloat(dt)
            clampPos()
            applyFrame()
        }
    }

    /// Glide toward the nearest screen corner for a cozy nap spot.
    private func glideToNearestCorner(_ dt: TimeInterval) {
        guard let w = window else { return }
        let fw = w.frame.width, fh = w.frame.height
        let corners: [NSPoint] = [
            NSPoint(x: boundsRect.minX, y: boundsRect.minY),
            NSPoint(x: boundsRect.maxX - fw, y: boundsRect.minY),
            NSPoint(x: boundsRect.minX, y: boundsRect.maxY - fh),
            NSPoint(x: boundsRect.maxX - fw, y: boundsRect.maxY - fh)
        ]
        let target = corners.min {
            hypot($0.x - pos.x, $0.y - pos.y) < hypot($1.x - pos.x, $1.y - pos.y)
        } ?? pos

        let dx = target.x - pos.x
        let dy = target.y - pos.y
        let dist = hypot(dx, dy)

        if dist < 3 {
            pos = target
            applyFrame()
            if !vm.facingLeft { vm.facingLeft = true }
            return
        }
        if abs(dx) > 2 { vm.facingLeft = dx < 0 }

        let step = Self.speed * 1.2 * CGFloat(dt)
        if dist <= step {
            pos = target
        } else {
            pos.x += (dx / dist) * step
            pos.y += (dy / dist) * step
        }
        clampPos()
        applyFrame()
    }

    private func clampPos() {
        guard let w = window else { return }
        pos.x = min(max(pos.x, boundsRect.minX), boundsRect.maxX - w.frame.width)
        pos.y = min(max(pos.y, boundsRect.minY), boundsRect.maxY - w.frame.height)
    }

    private func applyFrame() {
        guard let w = window else { return }
        // Skip when the origin already matches: repositioning two clear
        // floating panels 20×/s forces WindowServer recomposites even when
        // the buddy is standing still (e.g. napping in a corner).
        if let appliedOrigin,
           abs(appliedOrigin.x - pos.x) < 0.5, abs(appliedOrigin.y - pos.y) < 0.5 {
            return
        }
        w.setFrameOrigin(pos)
        noticePanel?.reposition()
        appliedOrigin = pos
    }

    // Called by the container view during interaction.

    fileprivate func handleTap() {
        guard let pet, pet.snapshot.species != nil else { return }
        if pet.snapshot.sleeping {
            pet.toggleSleep() // wake up
        } else {
            _ = pet.pet()
            vm.petPulse += 1
            vm.spawnHearts(3)
            vm.spawnMove(pet: pet)
        }
    }

    fileprivate func dragBegan() {
        isDragging = true
        walking = false
        // Grabbing a buddy mid-flight catches it out of the air.
        cancelFlight()
        dragSamples = [(Date(), NSEvent.mouseLocation)]
    }

    fileprivate func dragMoved(to point: CGPoint) {
        pos = point
        clampPos()
        applyFrame()
        let now = Date()
        dragSamples.append((now, point))
        while dragSamples.count > 2,
              let first = dragSamples.first,
              now.timeIntervalSince(first.time) > 0.09 {
            dragSamples.removeFirst()
        }
    }

    fileprivate func dragEnded() {
        isDragging = false
        remaining = Double.random(in: 1...2.5)
        let velocity = DesktopThrowSupport.releaseVelocity(samples: dragSamples)
        dragSamples = []
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        if speed >= Self.minThrowSpeed {
            beginThrow(vx: velocity.dx, vy: velocity.dy)
        } else {
            pet?.setDesktopPos(x: Double(pos.x), y: Double(pos.y))
        }
    }
}

// MARK: - Buddy throw physics

extension DesktopPetController {
    static let minThrowSpeed: Double = 380

    /// Winged species don't fall: a toss glides to a hover and the buddy
    /// keeps living at whatever altitude it stopped at.
    private var petFloats: Bool {
        guard let id = pet?.dexID else { return false }
        return PetAnimationEngine.motion(for: id)?.hasWings == true
    }

    /// Launches the buddy with the release flick; it then flies, bounces and
    /// rolls with the Ball.app desk-toy feel (floaters glide instead).
    private func beginThrow(vx: Double, vy: Double) {
        cancelFlight()
        vm.thrown = true
        vm.throwTumble = 0
        vm.walking = false
        flightState = DesktopThrowSupport.State(
            x: Double(pos.x), y: Double(pos.y), vx: vx, vy: vy
        )
        flightLastStepAt = Date()
        flightAccumulator = 0
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.stepThrow()
        }
        t.tolerance = 0.004
        RunLoop.main.add(t, forMode: .common)
        flightTimer = t
    }

    /// One timer tick: drain the accumulator in fixed substeps so the arc
    /// feels identical at any frame rate.
    private func stepThrow() {
        guard var state = flightState else { return }
        let now = Date()
        var dt = now.timeIntervalSince(flightLastStepAt)
        flightLastStepAt = now
        dt = min(0.1, dt)
        flightAccumulator += dt

        let substep = 1.0 / 120.0
        let box = window?.frame.size ?? CGSize(width: 170, height: 170)
        let floats = petFloats
        while flightAccumulator >= substep, flightState != nil {
            flightAccumulator -= substep
            let (next, events) = DesktopThrowSupport.step(
                state, dt: substep, box: box, bounds: boundsRect, floats: floats
            )
            state = next
            if events.hitFloor || events.hitCeiling {
                vm.impactCount += 1
            }
            if events.hitWall || events.hitFloor || events.hitCeiling {
                // A bounce kicks up dizzy stars only when it was hard enough
                // to hurt: the impact squash plays regardless.
                if abs(state.vy) > 260 || abs(state.vx) > 420 {
                    vm.spawnDizzy()
                }
            }
            // Tumble through the air like the thrown ball rolls.
            let speed = (state.vx * state.vx + state.vy * state.vy).squareRoot()
            if speed > 1 {
                let direction: Double = state.vx >= 0 ? 1 : -1
                vm.throwTumble += direction
                    * (520 + speed * 0.22) * substep
            }
            pos = CGPoint(x: state.x, y: state.y)
            applyFrame()
            if events.landed, abs(state.vx) < 0.5, abs(state.vy) < 0.5 {
                settleFromThrow(at: state)
                return
            }
        }
        flightState = state
    }

    /// The buddy came to rest: save the spot, shake off the stars, resume life.
    private func settleFromThrow(at state: DesktopThrowSupport.State) {
        cancelFlight()
        pos = CGPoint(x: state.x, y: state.y)
        clampPos()
        applyFrame()
        pet?.setDesktopPos(x: Double(pos.x), y: Double(pos.y))
        remaining = Double.random(in: 2...4)
        // A floater eases to a hover; only a grounded crash-landing dazes.
        if !petFloats { vm.spawnDizzy() }
        vm.thrown = false
    }

    /// Stops the sim where it is (a mid-air grab or teardown), keeping position.
    private func cancelFlight() {
        flightTimer?.invalidate()
        flightTimer = nil
        flightState = nil
        flightAccumulator = 0
        if vm.thrown {
            vm.thrown = false
            pet?.setDesktopPos(x: Double(pos.x), y: Double(pos.y))
        }
    }
}

// MARK: - Interaction view (click = pet, drag = move)

final class DesktopContainerView: NSView {
    private unowned let controller: DesktopPetController
    private var dragStartGlobal = NSPoint.zero
    private var frameStartOrigin = NSPoint.zero
    private var didMove = false

    init(frame: NSRect, controller: DesktopPetController) {
        self.controller = controller
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func mouseDown(with event: NSEvent) {
        dragStartGlobal = NSEvent.mouseLocation
        frameStartOrigin = window?.frame.origin ?? .zero
        didMove = false
    }

    override func mouseDragged(with event: NSEvent) {
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStartGlobal.x
        let dy = now.y - dragStartGlobal.y
        if !didMove && hypot(dx, dy) > 4 {
            didMove = true
            controller.dragBegan()
        }
        if didMove {
            controller.dragMoved(to: NSPoint(x: frameStartOrigin.x + dx, y: frameStartOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if didMove {
            controller.dragEnded()
        } else {
            controller.handleTap()
        }
    }
}

final class PetPassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Sprite view

struct DesktopPetView: View {
    @EnvironmentObject private var vm: DesktopViewModel
    @EnvironmentObject private var pet: PetState

    /// Deliberately small — the buddy reads as a pocket creature, and pixel
    /// art keeps its details at this size. Normalization (PetSpriteMetrics)
    /// evens out species-to-species differences on top of this.
    static let buddySpriteHeight: CGFloat = 76

    /// When the current joy dance started; nil while the buddy is calm.
    @State private var joyStart: Date?

    /// Bumped whenever any sprite finishes decoding: the normalization scale
    /// lives in this view (so it can wrap sprite + eyelids together) and must
    /// recompute once real frames exist.
    @State private var spriteEpoch = false
    /// True for a beat after each floor bounce: the landing squash.
    @State private var impactSquash = false
    /// Start of the startled hop that greets a new system notification.
    @State private var noticeHopStart: Date?
    /// Start of the current pet-tap reaction and the flavour that tap picked.
    @State private var petReactStart: Date?
    @State private var petReaction: PetTapReaction = .bounce

    /// True while a blink has the lids shut; driven by a scheduled task, so
    /// between blinks nothing renders at all.
    @State private var eyesClosed = false
    @State private var blinkCount = 0
    /// Settings toggle for the whole eyelid overlay (blinks and sleep lids).
    @AppStorage(DefaultsKey.desktopPetBlinks) private var blinksEnabled = true

    /// Motion only matters while walking, napping or celebrating — outside of
    /// that the timeline is paused so a calm buddy costs no redraws. A hidden
    /// buddy pauses everything.
    private var timelinePaused: Bool {
        !vm.buddyVisible || !(vm.walking || pet.snapshot.sleeping || joyStart != nil
                              || vm.thrown || noticeHopStart != nil
                              || petReactStart != nil)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: joyStart == nil || !vm.buddyVisible)) { timeline in
                    Capsule()
                        .fill(Color.black.opacity(0.14))
                        .frame(width: 52, height: 7)
                        .blur(radius: 3)
                        .padding(.bottom, 26)
                        .scaleEffect(shadowScale(at: timeline.date))
                }
            }

            // Sleep breathing is a slow sine: 10 fps is indistinguishable
            // from 30 here and costs a third of the redraws during naps
            // that can last hours.
            TimelineView(
                .animation(
                    // The nap choreography (breath waves + dream kicks)
                    // needs smoother sampling than the old flat sine:
                    // 15 fps is a third of the awake cost, still fluid.
                    minimumInterval: pet.snapshot.sleeping ? 1.0 / 15 : 1.0 / 30,
                    paused: timelinePaused
                )
            ) { timeline in
                let now = timeline.date
                sprite
                    .rotationEffect(
                        .degrees(vm.thrown ? vm.throwTumble : 0),
                        anchor: .center
                    )
                    .scaleEffect(
                        x: impactSquash ? 1.14 : 1,
                        y: impactSquash ? 0.78 : 1,
                        anchor: .bottom
                    )
                    // Petting squash & stretch rides its own axis pair — the
                    // shared bodyScale is uniform and can't flatten a body.
                    .scaleEffect(
                        x: petReactScaleX(at: now),
                        y: petReactScaleY(at: now),
                        anchor: .bottom
                    )
                    .offset(y: bodyOffset(at: now))
                    .offset(x: bodyXShift(at: now))
                    .scaleEffect(bodyScale(at: now), anchor: .bottom)
                    .rotationEffect(.degrees(bodyRotation(at: now)), anchor: .bottom)
            }
            .onChange(of: vm.impactCount) { _ in
                guard vm.thrown else { return }
                withAnimation(.easeOut(duration: 0.07)) { impactSquash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
                        impactSquash = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pokePalCelebrate)) { _ in
                joyStart = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    joyStart = nil
                }
            }

            ForEach(vm.hearts) { heart in
                FloatingHeartView(heart: heart) {
                    vm.hearts.removeAll { $0.id == heart.id }
                }
            }

            ForEach(vm.moves) { move in
                PetMoveEffectView(move: move) {
                    vm.moves.removeAll { $0.id == move.id }
                }
                .offset(
                    x: vm.facingLeft ? -58 : 28,
                    y: pet.snapshot.sleeping ? 0 : -22
                )
            }

            ForEach(vm.zzzs) { zzz in
                FloatingZzzView(zzz: zzz) {
                    vm.zzzs.removeAll { $0.id == zzz.id }
                }
            }

            ForEach(vm.fetched) { fetch in
                FloatingFetchView(fetch: fetch) {
                    vm.fetched.removeAll { $0.id == fetch.id }
                }
                .offset(y: pet.snapshot.sleeping ? 10 : -18)
            }

            ForEach(vm.dizzyStars) { star in
                FloatingDizzyView(star: star) {
                    vm.dizzyStars.removeAll { $0.id == star.id }
                }
            }

            if pet.snapshot.sleeping {
                SleepBubble()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 30)
                    .padding(.top, 26)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spriteCacheDidUpdate)) { _ in
            // Re-evaluates body so the normalization scale recomputes now
            // that real frames exist.
            spriteEpoch.toggle()
        }
        .onReceive(vm.$petPulse.dropFirst()) { pulse in
            // A petting tap: the body answers with a squish, shimmy or hop.
            // Sleep taps wake instead (handled at the tap), and a mid-air
            // buddy already has the throw physics animating it.
            guard !pet.snapshot.sleeping, !vm.thrown else { return }
            petReaction = PetTapReaction.pick(pulse: pulse, seed: pet.dexID ?? 0)
            petReactStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + PetTapReaction.duration + 0.05) {
                if let start = petReactStart,
                   Date().timeIntervalSince(start) >= PetTapReaction.duration {
                    petReactStart = nil
                }
            }
        }
        .onReceive(vm.$alertPulse.dropFirst()) { _ in
            // A system notification just reached the buddy: a startled
            // double-hop toward its banner.
            noticeHopStart = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let start = noticeHopStart,
                   Date().timeIntervalSince(start) >= 0.95 {
                    noticeHopStart = nil
                }
            }
        }
    }

    @ViewBuilder
    private var sprite: some View {
        if let id = pet.dexID {
            let motion = PetAnimationEngine.motion(for: id)
            // One normalization for the whole stack: the sprite's visible
            // artwork lands on a common fraction of the box no matter how
            // much padding its source canvas carries, and the eyelids ride
            // the same transform so they never drift off the face.
            let frames = SpriteCache.frames(for: id) ?? []
            let placement = PetSpriteMetrics.placement(for: id, frames: frames)
            let fit = CGFloat(placement.scale)
            let aspect = frames.first.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1
            ZStack {
                AnimatedSpriteView(
                    id: id,
                    height: Self.buddySpriteHeight,
                    sleeping: pet.snapshot.sleeping,
                    legMotion: motion,
                    walking: vm.walking,
                    flying: flying,
                    // Frozen while asleep: the GIF's own idle frames would
                    // bob the face under the fixed eyelid rects. Frame 0 is
                    // the neutral pose the eye rects were measured on.
                    paused: !vm.buddyVisible || pet.snapshot.sleeping,
                    normalizeSize: false
                )
                // Eyelids sit inside the same flipped, offset, scaled
                // hierarchy as the sprite, so they track every body motion.
                // Skipped when the art already draws the eyes shut or as a
                // squint (a lid there is a smudge, not a blink), and when
                // the settings toggle turns the overlay off.
                if let motion, blinksEnabled,
                   PetAnimationPackSupport.eyesWorthAnimating(motion) {
                    PetEyelidsView(
                        motion: motion,
                        height: Self.buddySpriteHeight,
                        closed: eyesClosed || pet.snapshot.sleeping,
                        sleeping: pet.snapshot.sleeping
                    )
                }
            }
            // Sink the canvas' empty bottom margin so feet actually touch the
            // ground (gen 6+ PNGs carry up to a third of the canvas below the
            // art), and pull off-centre artwork back over the shadow. Applied
            // before the bottom-anchored scale, which multiplies both shifts.
            .offset(
                x: CGFloat(placement.centerDX) * Self.buddySpriteHeight * aspect,
                y: CGFloat(placement.bottomMargin) * Self.buddySpriteHeight
            )
            .scaleEffect(fit, anchor: .bottom)
            // The tip-over judges the visible artwork, not the canvas: a
            // padded PNG's canvas is square however round its body is, and
            // lifting by half the canvas width left sleepers in mid-air.
            .modifier(PetSleepPose(
                sleeping: pet.snapshot.sleeping,
                widthOverHeight: placement.artWidthOverHeight,
                spriteHeight: Self.buddySpriteHeight * CGFloat(placement.visibleHeightFraction)
            ))
            // PokeAPI front sprites natively face LEFT, so the mirror is
            // what turns a buddy to the right: facing left draws the raw
            // sprite untouched, and it waddles the way it looks.
            .scaleEffect(x: vm.facingLeft ? 1 : -1, anchor: .center)
            .task(id: id) { await runBlinks(for: id) }
        }
    }

    /// Winged species travel by air: a smooth hover with a gentle pitch into
    /// the direction of travel instead of ground steps.
    private var flying: Bool {
        guard vm.walking, !pet.snapshot.sleeping, let id = pet.dexID else { return false }
        return PetAnimationEngine.motion(for: id)?.hasWings == true
    }

    /// Schedules blinks a few seconds apart. One sleeping task, no timers:
    /// each flip is a two-frame Core Animation transition, and while the
    /// buddy sleeps the loop just idles with the lids held shut.
    private func runBlinks(for id: Int) async {
        let period = PetAnimationPackSupport.blinkPeriod(for: id)
        while !Task.isCancelled {
            // No pack entry, eyes drawn shut in the art, or the toggle off:
            // no blinking at all — just idle cheaply and watch for changes.
            let motion = PetAnimationEngine.motion(for: id)
            if motion == nil || !blinksEnabled
                || !PetAnimationPackSupport.eyesWorthAnimating(motion!) {
                if eyesClosed { eyesClosed = false }
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            if pet.snapshot.sleeping {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let openFor = period * Double.random(in: 0.75...1.3)
            try? await Task.sleep(for: .seconds(openFor))
            guard !Task.isCancelled, !pet.snapshot.sleeping else { continue }
            blinkCount += 1
            withAnimation(.easeInOut(duration: 0.06)) { eyesClosed = true }
            try? await Task.sleep(for: .seconds(PetAnimationPackSupport.blinkClosedDuration))
            withAnimation(.easeInOut(duration: 0.08)) { eyesClosed = false }
            // Every so often a quick second blink — the way eyes really do.
            let doubleBlink = (blinkCount + id) % 4 == 0
            if doubleBlink, !Task.isCancelled, !pet.snapshot.sleeping {
                try? await Task.sleep(for: .seconds(0.18))
                withAnimation(.easeInOut(duration: 0.05)) { eyesClosed = true }
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.easeInOut(duration: 0.07)) { eyesClosed = false }
            }
        }
    }

    /// Walk-cycle flavor for the current species; `.neutral` (pack absent)
    /// keeps the original motion byte-for-byte.
    private var gait: PetGait {
        guard let id = pet.dexID, let motion = PetAnimationEngine.motion(for: id) else { return .neutral }
        return PetAnimationPackSupport.gait(forClass: motion.gaitClass)
    }

    // MARK: Body motion

    /// True while the buddy is striding on its sliced legs — the body stays
    /// level and lets the legs do the talking instead of waddling.
    private var stepping: Bool {
        vm.walking && !pet.snapshot.sleeping && !flying && steppingOnLegs
    }

    private var steppingOnLegs: Bool {
        guard let id = pet.dexID else { return false }
        return PetAnimationEngine.motion(for: id)?.hasLegs == true
    }

    private func bodyOffset(at now: Date) -> CGFloat {
        var y = 0.0
        let t = now.timeIntervalSinceReferenceDate
        let gait = gait

        // The sleep routine owns the body while asleep: breathing waves and
        // dream twitches ride the same transform chain as the lids.
        if pet.snapshot.sleeping {
            let nap = PetSleepChoreography.pose(at: t, seed: pet.dexID ?? 0, gaitClass: gait.gaitClass)
            return CGFloat(-nap.yOffset)
        }

        if vm.walking, !pet.snapshot.sleeping {
            if flying {
                // Flyers glide.
                y -= 7 + sin(t * 2.8) * 3.5
            } else if stepping {
                // Legs swing; the body just breathes with the stride.
                let phase = t * 9 * gait.stepRate
                y -= abs(sin(phase)) * 1.1
            } else {
                // Pack-free fallback keeps the classic hop.
                y -= abs(sin(t * 9 * gait.stepRate)) * 5 * gait.bobAmplitude
            }
        }

        // Joyful: three quick decaying hops. Squat buddies shake where they
        // stand; tall ones really get air.
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                let flavour: Double = gait.gaitClass == 0 ? 0.45 : (gait.gaitClass == 2 ? 1.25 : 1.0)
                y -= max(0, sin(dt * .pi * 4)) * 16 * flavour * exp(-dt * 1.8)
            }
        }

        // A new notification lands: two sharp little start hops.
        if let noticeHopStart {
            let dt = now.timeIntervalSince(noticeHopStart)
            if dt < 0.9 {
                y -= abs(sin(dt * .pi * 5)) * 7 * exp(-dt * 2.2)
            }
        }

        // A petting tap: the reaction's own lift (delight hops).
        if let petReactStart {
            y += petReaction.offsetY(
                at: now.timeIntervalSince(petReactStart),
                height: Double(Self.buddySpriteHeight)
            )
        }
        return CGFloat(y)
    }

    private func petReactScaleX(at now: Date) -> CGFloat {
        guard let petReactStart else { return 1 }
        return CGFloat(petReaction.scaleX(at: now.timeIntervalSince(petReactStart)))
    }

    private func petReactScaleY(at now: Date) -> CGFloat {
        guard let petReactStart else { return 1 }
        return CGFloat(petReaction.scaleY(at: now.timeIntervalSince(petReactStart)))
    }

    /// Sideways drift from dream twitches — zero while awake.
    private func bodyXShift(at now: Date) -> CGFloat {
        guard pet.snapshot.sleeping else { return 0 }
        return CGFloat(PetSleepChoreography.pose(
            at: now.timeIntervalSinceReferenceDate,
            seed: pet.dexID ?? 0,
            gaitClass: gait.gaitClass
        ).xOffset)
    }

    private func bodyRotation(at now: Date) -> Double {
        var angle = 0.0
        let t = now.timeIntervalSinceReferenceDate
        let gait = gait

        // Sleepy heads nod: tall species droop forward as they doze — and
        // the choreography layers settling shifts + dream twitches on top.
        if pet.snapshot.sleeping {
            let nap = PetSleepChoreography.pose(at: t, seed: pet.dexID ?? 0, gaitClass: gait.gaitClass)
            return (gait.gaitClass == 2 ? (vm.facingLeft ? 1.8 : -1.8) : 0) + nap.angle
        }

        // Flyers bank into travel; striders stay near-level with a faint
        // counter-sway; the pack-free fallback keeps the classic waddle.
        if vm.walking, !pet.snapshot.sleeping {
            if flying {
                angle += (vm.facingLeft ? 5 : -5) + sin(t * 2.8 + 0.9) * 2
            } else if stepping {
                angle += sin(t * 9 * gait.stepRate) * 0.7
            } else {
                angle += sin(t * 9 * gait.stepRate) * 2.5 * gait.waddle
            }
        }

        // Joy wiggle on top of the hops — squigglier for squat species.
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                let wiggle: Double = gait.gaitClass == 0 ? 10 : 7
                angle += sin(dt * .pi * 6) * wiggle * exp(-dt * 2.2)
            }
        }

        // A petting tap: the reaction's shimmy or hop lean.
        if let petReactStart {
            angle += petReaction.rotation(
                at: now.timeIntervalSince(petReactStart),
                facingLeft: vm.facingLeft
            )
        }
        return angle
    }

    /// Asleep: the choreographed breath — waves of deeper and lighter
    /// breathing, not one flat sine. Celebrating: a landing squash between
    /// hops. Flying: a fast wing-beat flutter.
    private func bodyScale(at now: Date) -> Double {
        if pet.snapshot.sleeping {
            return PetSleepChoreography.pose(
                at: now.timeIntervalSinceReferenceDate,
                seed: pet.dexID ?? 0,
                gaitClass: gait.gaitClass
            ).breathScale
        }
        if flying {
            return 1 + 0.022 * sin(now.timeIntervalSinceReferenceDate * 8.5)
        }
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                return 1 + 0.06 * sin(dt * .pi * 8) * exp(-dt * 2.5)
            }
        }
        return 1
    }

    /// The floor shadow shrinks while airborne so hops read as real lifts —
    /// and stays small while a flyer is aloft.
    private func shadowScale(at now: Date) -> Double {
        if flying {
            return 0.45
        }
        guard let joyStart else { return 1 }
        let dt = now.timeIntervalSince(joyStart)
        guard dt < 1.5 else { return 1 }
        return 1 - 0.35 * max(0, sin(dt * .pi * 4)) * exp(-dt * 1.8)
    }
}

// MARK: - Sleep pose (lying down)

/// The nap pose, applied to the whole sprite-and-eyelids stack so the lids
/// ride every degree of it: upright buddies tip over onto their side and
/// settle onto the floor, round ones curl up where they sit. The GIF frames
/// freeze while asleep (`AnimatedSpriteView.paused`), so the pose is
/// genuinely still — only the outer breathing scale moves, and it moves
/// sprite and lids together.
struct PetSleepPose: ViewModifier {
    let sleeping: Bool
    let widthOverHeight: Double
    /// Display height AFTER size normalization — the tip-over lift is half
    /// the buddy's real width, so it needs the scaled number.
    var spriteHeight: CGFloat = 96

    func body(content: Content) -> some View {
        let pose = PetAnimationPackSupport.sleepPose(
            canvasWidthOverHeight: widthOverHeight,
            spriteHeight: Double(spriteHeight)
        )
        content
            .rotationEffect(
                .degrees(sleeping ? pose.rotationDegrees : 0),
                anchor: .bottom
            )
            .offset(y: sleeping ? pose.liftY : 0)
            .animation(.easeInOut(duration: 0.45), value: sleeping)
    }
}

// MARK: - Eyelid overlay (animation pack)

/// Draws the buddy's eyelids over its sprite: brief closures while awake
/// (blinking) and a steady gentle shut while asleep. The lid is painted in
/// the species' own sampled fur colour, so slight over-coverage melts into
/// the body; only the darker lash line carries the shape. Fades in and out
/// with plain Core Animation transitions — no render loop of its own.
///
/// Geometry comes from `PetAnimationPackSupport.lidRects`, which grows the
/// measured eye box a touch: drawn at exactly the measured size, the eye's
/// sclera and outline ring stayed visible around the lid and the buddy
/// napped with its eyes half open.
struct PetEyelidsView: View {
    let motion: PetFaceMotion
    let height: CGFloat
    let closed: Bool
    /// Lids share the sprite's sleep tint; see `PetSleepTint`.
    var sleeping = false

    var body: some View {
        let canvasWidth = height * CGFloat(motion.widthOverHeight)
        ZStack {
            if let rects = PetAnimationPackSupport.lidRects(for: motion),
               let left = motion.leftEye, let right = motion.rightEye {
                lid(rects.left, lash: left)
                lid(rects.right, lash: right)
            }
        }
        .frame(width: canvasWidth, height: height)
        .opacity(closed ? 1 : 0)
        .petSleepTint(sleeping)
        .allowsHitTesting(false)
    }

    /// One shut eye: fur over the whole grown lid box, and the lash line
    /// sized off the *measured* eye instead of the grown box. Scaling the
    /// lash with the fur turned every wide lid into a black bar — sunglasses,
    /// not sleep — while the fur itself, being the species' own colour, can
    /// spread as far as it needs to without being seen.
    @ViewBuilder
    private func lid(_ fill: PetEyeRect, lash eye: PetEyeRect) -> some View {
        let canvasWidth = height * CGFloat(motion.widthOverHeight)
        let width = CGFloat(fill.width) * canvasWidth
        let lidHeight = CGFloat(fill.height) * height
        let x = (CGFloat(fill.x) + CGFloat(fill.width) / 2) * canvasWidth
        let y = (CGFloat(fill.y) + CGFloat(fill.height) / 2) * height
        let lashWidth = CGFloat(eye.width) * canvasWidth
        // Centred on the eye, not on the lid: the unibrow trim can pull one
        // side of a close-set lid in, and the lash must stay on the eye.
        let lashCentreX = (CGFloat(eye.x) + CGFloat(eye.width) / 2) * canvasWidth
        let lashCentreY = (CGFloat(eye.y) + CGFloat(eye.height) / 2) * height
        let color = motion.lidColor
        ZStack {
            // Barely rounded: at the old 0.3 the corners cut back inside the
            // eye and left four crumbs of it showing.
            RoundedRectangle(cornerRadius: lidHeight * 0.16)
                .fill(Color(red: color.red, green: color.green, blue: color.blue))
            // Lash line along the lower lid: the part that actually reads.
            Capsule()
                .fill(Color(red: color.red * 0.42, green: color.green * 0.42, blue: color.blue * 0.42))
                .frame(
                    width: lashWidth * 0.84,
                    height: max(1.1, CGFloat(eye.height) * height * 0.24)
                )
                .offset(
                    x: lashCentreX - x,
                    y: lashCentreY - y + CGFloat(eye.height) * height * 0.34
                )
        }
        .frame(width: width, height: lidHeight)
        .position(x: x, y: y)
    }
}
