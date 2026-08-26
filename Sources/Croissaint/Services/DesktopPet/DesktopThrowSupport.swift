// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import CoreGraphics
import Foundation

/// Real-life physics for hurling the buddy across the desktop, tuned to feel
/// like the wild-encounter ball throw (`WildSpawnController.ThrowPhysics`):
/// fixed-step integration, gravity, horizontal air drag, bouncy walls and a
/// floor that turns the bounce into a rolling skid.
///
/// Coordinates are Cocoa screen points, y increasing upward. The moving box
/// is the buddy's whole window; `bounds` is the visible-frame rect the window
/// must stay inside.
enum DesktopThrowSupport {
    struct State: Equatable {
        var x: Double      // window origin, left edge
        var y: Double      // window origin, bottom edge (Cocoa y-up)
        var vx: Double     // points per second
        var vy: Double

        static let atRest = State(x: 0, y: 0, vx: 0, vy: 0)
    }

    /// One-step happenings the UI reacts to (impact squash, dizzy stars…).
    struct Events: Equatable {
        var hitFloor = false
        var hitWall = false
        var hitCeiling = false
        /// Set exactly once, the step the buddy comes fully to rest.
        var landed = false
    }

    struct Constants {
        static let gravity: Double = 1500          // pt/s², matches the ball arc
        static let airDrag: Double = 0.9           // fraction of vx lost per second
        static let wallRestitution: Double = 0.62
        static let ceilingRestitution: Double = 0.45
        static let floorRestitution: Double = 0.52
        /// Bounces slower than this collapse into a ground skid instead.
        static let bounceCutoff: Double = 110
        static let rollFriction: Double = 850      // pt/s² against the ground
        /// Below this ground speed the buddy stops pretending to roll.
        static let restSpeed: Double = 26
    }

    /// Integrates one fixed step. `box` is the window size; `bounds` the
    /// rect origins are clamped into. Returns the new state plus what happened.
    static func step(
        _ s: State, dt: Double, box: CGSize, bounds: CGRect
    ) -> (state: State, events: Events) {
        var st = s
        var events = Events()

        // Forces.
        st.vy -= Constants.gravity * dt
        st.vx *= max(0, 1 - Constants.airDrag * dt)

        // Integrate.
        st.x += st.vx * dt
        st.y += st.vy * dt

        let maxX = Double(bounds.maxX - box.width)
        let maxY = Double(bounds.maxY - box.height)

        // Walls.
        if st.x < Double(bounds.minX) {
            st.x = Double(bounds.minX)
            st.vx = abs(st.vx) * Constants.wallRestitution
            events.hitWall = true
        } else if st.x > maxX {
            st.x = maxX
            st.vx = -abs(st.vx) * Constants.wallRestitution
            events.hitWall = true
        }

        // Ceiling.
        if st.y > maxY, st.vy > 0 {
            st.y = maxY
            st.vy = -st.vy * Constants.ceilingRestitution
            events.hitCeiling = true
        }

        // Floor: bounce, or collapse into a rolling skid.
        if st.y <= Double(bounds.minY), st.vy < 0 {
            st.y = Double(bounds.minY)
            if -st.vy > Constants.bounceCutoff {
                st.vy = -st.vy * Constants.floorRestitution
                events.hitFloor = true
            } else {
                st.vy = 0
            }
        }

        // Ground friction while rolling.
        let onGround = st.y <= Double(bounds.minY) + 0.5 && abs(st.vy) < 0.5
        if onGround, st.vx != 0 {
            let drop = Constants.rollFriction * dt
            if abs(st.vx) <= drop + Constants.restSpeed {
                st.vx = 0
            } else {
                st.vx -= (st.vx > 0 ? drop : -drop)
            }
            if st.vx == 0 {
                events.landed = true
            }
        } else if onGround, st.vx == 0 {
            events.landed = true
        }

        return (st, events)
    }

    /// Launch velocity from drag samples: mean velocity over the trailing
    /// `window` seconds, ignoring stale points and stalls. Mirrors how the
    /// ball throw reads a flick instead of trusting one delta.
    static func releaseVelocity(
        samples: [(time: Date, point: CGPoint)]
    ) -> (dx: Double, dy: Double) {
        guard samples.count >= 2,
              let first = samples.first, let last = samples.last
        else { return (0, 0) }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0.012 else { return (0, 0) }
        return (
            Double(last.point.x - first.point.x) / dt,
            Double(last.point.y - first.point.y) / dt
        )
    }
}
