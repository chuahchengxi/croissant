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
    @Published var moves: [PetMoveInstance] = []
    @Published var notice: PetNotice?

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
    func showNotice(text: String, icon: NSImage?) {
        let notice = PetNotice(text: PetPixelArt.text(text), icon: icon.flatMap(PetPixelArt.icon))
        withAnimation(.easeOut(duration: 0.25)) {
            self.notice = notice
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            withAnimation(.easeIn(duration: 0.3)) {
                if self?.notice?.id == notice.id { self?.notice = nil }
            }
        }
    }

    /// A sleepy "z" drifting off the buddy. Old ones are trimmed so a long
    /// nap never accumulates views.
    func spawnZzz() {
        zzzs.append(FloatingZzz(x: .random(in: 24...46), size: .random(in: 9...14)))
        if zzzs.count > 5 { zzzs.removeFirst(zzzs.count - 5) }
    }
}

/// One drifting "z" puff while the buddy naps.
struct FloatingZzz: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
}

struct FloatingZzzView: View {
    let zzz: FloatingZzz
    let onDone: () -> Void
    @State private var risen = false

    var body: some View {
        Text("z")
            .font(.system(size: zzz.size, weight: .black, design: .rounded))
            .foregroundStyle(.indigo.opacity(0.85))
            .padding(.horizontal, 3)
            .background(Capsule().fill(Color.white.opacity(0.75)))
            .offset(x: zzz.x + (risen ? 8 : 0), y: risen ? -52 : 6)
            .opacity(risen ? 0 : 0.95)
            .scaleEffect(risen ? 1.15 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) { risen = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) { onDone() }
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
    }

    /// Tears the walker down: stops ticking and takes the window off screen,
    /// so a disabled feature leaves nothing on the display or in the CPU.
    func stop() {
        timer?.invalidate()
        timer = nil
        PetNotificationBridge.shared.stop()
        noticeCancellable?.cancel()
        noticeCancellable = nil
        noticePanel?.stop()
        noticePanel = nil
        if let celebrateToken {
            NotificationCenter.default.removeObserver(celebrateToken)
            self.celebrateToken = nil
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
            // Snore on a beat: a "z" puff every couple of seconds.
            if Date() >= nextZzzAt {
                vm.spawnZzz()
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
            vm.spawnHearts(3)
            vm.spawnMove(pet: pet)
        }
    }

    fileprivate func dragBegan() { isDragging = true; walking = false }
    fileprivate func dragMoved(to point: CGPoint) { pos = point; clampPos(); applyFrame() }
    fileprivate func dragEnded() {
        isDragging = false
        remaining = Double.random(in: 1...2.5)
        pet?.setDesktopPos(x: Double(pos.x), y: Double(pos.y))
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

    /// When the current joy dance started; nil while the buddy is calm.
    @State private var joyStart: Date?

    /// True while a blink has the lids shut; driven by a scheduled task, so
    /// between blinks nothing renders at all.
    @State private var eyesClosed = false
    @State private var blinkCount = 0

    /// Motion only matters while walking, napping or celebrating — outside of
    /// that the timeline is paused so a calm buddy costs no redraws. A hidden
    /// buddy pauses everything.
    private var timelinePaused: Bool {
        !vm.buddyVisible || !(vm.walking || pet.snapshot.sleeping || joyStart != nil)
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
                    minimumInterval: pet.snapshot.sleeping ? 1.0 / 10 : 1.0 / 30,
                    paused: timelinePaused
                )
            ) { timeline in
                let now = timeline.date
                sprite
                    .offset(y: bodyOffset(at: now))
                    .scaleEffect(bodyScale(at: now), anchor: .bottom)
                    .rotationEffect(.degrees(bodyRotation(at: now)), anchor: .bottom)
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

            if pet.snapshot.sleeping {
                SleepBubble()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 30)
                    .padding(.top, 26)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var sprite: some View {
        if let id = pet.dexID {
            let motion = PetAnimationEngine.motion(for: id)
            ZStack {
                AnimatedSpriteView(
                    id: id,
                    height: 96,
                    sleeping: pet.snapshot.sleeping,
                    legMotion: motion,
                    walking: vm.walking,
                    flying: flying,
                    // Frozen while asleep: the GIF's own idle frames would
                    // bob the face under the fixed eyelid rects. Frame 0 is
                    // the neutral pose the eye rects were measured on.
                    paused: !vm.buddyVisible || pet.snapshot.sleeping
                )
                // Eyelids sit inside the same flipped, offset, scaled
                // hierarchy as the sprite, so they track every body motion.
                if let motion {
                    PetEyelidsView(
                        motion: motion,
                        height: 96,
                        closed: eyesClosed || pet.snapshot.sleeping,
                        sleeping: pet.snapshot.sleeping
                    )
                }
            }
            .modifier(PetSleepPose(
                sleeping: pet.snapshot.sleeping,
                widthOverHeight: motion?.widthOverHeight ?? 1
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
            if PetAnimationEngine.motion(for: id) == nil {
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
        return CGFloat(y)
    }

    private func bodyRotation(at now: Date) -> Double {
        var angle = 0.0
        let t = now.timeIntervalSinceReferenceDate
        let gait = gait

        // Sleepy heads nod: tall species droop forward as they doze.
        if pet.snapshot.sleeping, gait.gaitClass == 2 {
            angle += vm.facingLeft ? 1.8 : -1.8
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
        return angle
    }

    /// Asleep: slow breathing. Celebrating: a landing squash between hops.
    /// Flying: a fast wing-beat flutter.
    private func bodyScale(at now: Date) -> Double {
        if pet.snapshot.sleeping {
            let base = gait.gaitClass == 0 ? 0.965 : 1.0
            return base + 0.03 * sin(now.timeIntervalSinceReferenceDate * 2.2)
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
    static let spriteHeight: CGFloat = 96

    func body(content: Content) -> some View {
        let pose = PetAnimationPackSupport.sleepPose(
            canvasWidthOverHeight: widthOverHeight,
            spriteHeight: Double(Self.spriteHeight)
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
