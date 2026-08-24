// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import AppKit
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
    @Published var facingLeft = false
    @Published var walking = false
    @Published var hearts: [FloatingHeart] = []
    @Published var zzzs: [FloatingZzz] = []

    func spawnHearts(_ count: Int) {
        for _ in 0..<count {
            hearts.append(FloatingHeart(x: .random(in: -40...40), size: .random(in: 10...18)))
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
    private var walking = false
    private var dir = 1
    private var remaining: TimeInterval = 1.5
    private var isDragging = false
    private var pos = CGPoint.zero
    private var boundsRect = CGRect.zero
    private var isShown = false
    private var lastSleeping = false
    private var nextZzzAt = Date.distantPast
    private static let speed: CGFloat = 60 // px/s

    func start(pet: PetState) {
        guard timer == nil else { return }
        self.pet = pet
        computeBounds()
        setupWindow()

        if let saved = pet.desktopPos() {
            pos = CGPoint(x: CGFloat(saved.x), y: CGFloat(saved.y))
        } else if let screen = NSScreen.main?.visibleFrame {
            pos = CGPoint(x: screen.midX - 85, y: screen.minY + 12)
        }
        clampPos()
        applyFrame()

        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick(0.05)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        celebrateToken = NotificationCenter.default.addObserver(
            forName: .pokePalCelebrate, object: nil, queue: .main
        ) { [weak self] _ in
            self?.vm.spawnHearts(4)
        }
    }

    /// Tears the walker down: stops ticking and takes the window off screen,
    /// so a disabled feature leaves nothing on the display or in the CPU.
    func stop() {
        timer?.invalidate()
        timer = nil
        if let celebrateToken {
            NotificationCenter.default.removeObserver(celebrateToken)
            self.celebrateToken = nil
        }
        window?.orderOut(nil)
        isShown = false
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
    }

    func setVisible(_ visible: Bool) {
        if visible { window?.makeKeyAndOrderFront(nil) }
        else { window?.orderOut(nil) }
        isShown = window?.isVisible ?? false
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
        let shouldFaceLeft = dir == -1 && moving
        if vm.facingLeft != shouldFaceLeft { vm.facingLeft = shouldFaceLeft }

        if moving {
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
            if vm.facingLeft { vm.facingLeft = false }
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
        w.setFrameOrigin(pos)
    }

    // Called by the container view during interaction.

    fileprivate func handleTap() {
        guard let pet, pet.snapshot.species != nil else { return }
        if pet.snapshot.sleeping {
            pet.toggleSleep() // wake up
        } else {
            _ = pet.pet()
            vm.spawnHearts(3)
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

    /// Motion only matters while walking, napping or celebrating — outside of
    /// that the timeline is paused so a calm buddy costs no redraws.
    private var timelinePaused: Bool {
        !(vm.walking || pet.snapshot.sleeping || joyStart != nil)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: joyStart == nil)) { timeline in
                    Capsule()
                        .fill(Color.black.opacity(0.14))
                        .frame(width: 52, height: 7)
                        .blur(radius: 3)
                        .padding(.bottom, 26)
                        .scaleEffect(shadowScale(at: timeline.date))
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: timelinePaused)) { timeline in
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
            AnimatedSpriteView(id: id, height: 96, sleeping: pet.snapshot.sleeping)
                .scaleEffect(x: vm.facingLeft ? -1 : 1, anchor: .center)
        }
    }

    // MARK: Body motion

    private func bodyOffset(at now: Date) -> CGFloat {
        var y = 0.0
        let t = now.timeIntervalSinceReferenceDate

        // Walking: a bouncy step hop.
        if vm.walking, !pet.snapshot.sleeping {
            y -= abs(sin(t * 9)) * 5
        }

        // Joyful: three quick decaying hops.
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                y -= max(0, sin(dt * .pi * 4)) * 16 * exp(-dt * 1.8)
            }
        }
        return CGFloat(y)
    }

    private func bodyRotation(at now: Date) -> Double {
        var angle = 0.0
        let t = now.timeIntervalSinceReferenceDate

        // Waddle: tilt side to side with each step.
        if vm.walking, !pet.snapshot.sleeping {
            angle += sin(t * 9) * 2.5
        }

        // Joy wiggle on top of the hops.
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                angle += sin(dt * .pi * 6) * 7 * exp(-dt * 2.2)
            }
        }
        return angle
    }

    /// Asleep: slow breathing. Celebrating: a landing squash between hops.
    private func bodyScale(at now: Date) -> Double {
        if pet.snapshot.sleeping {
            return 1 + 0.03 * sin(now.timeIntervalSinceReferenceDate * 2.2)
        }
        if let joyStart {
            let dt = now.timeIntervalSince(joyStart)
            if dt < 1.5 {
                return 1 + 0.06 * sin(dt * .pi * 8) * exp(-dt * 2.5)
            }
        }
        return 1
    }

    /// The floor shadow shrinks while airborne so hops read as real lifts.
    private func shadowScale(at now: Date) -> Double {
        guard let joyStart else { return 1 }
        let dt = now.timeIntervalSince(joyStart)
        guard dt < 1.5 else { return 1 }
        return 1 - 0.35 * max(0, sin(dt * .pi * 4)) * exp(-dt * 1.8)
    }
}
