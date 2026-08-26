// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 chuahchengxi

import CoreGraphics
import Foundation

/// Real-life physics for hurling the buddy across the desktop, matched to the
/// Ball.app desk toy (nate-parrott/ball, `brew install --cask ball`): SpriteKit
/// gravity, uniform 0.6 restitution on every edge, and its default 0.1/s
/// linear damping — plus a floor skid so the buddy ends standing, and a
/// float mode where winged species glide to a hover instead of falling.
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
        /// SpriteKit's default field: 9.8 m/s² at 150 pt/m ≈ 1470.
        static let gravity: Double = 1500          // pt/s²
        /// Ball.app leaves SpriteKit's default damping: 0.1/s, both axes.
        static let linearDamping: Double = 0.1
        /// Ball.app: `body.restitution = 0.6`, one value for every edge.
        static let restitution: Double = 0.6
        /// Bounces slower than this collapse into a ground skid instead.
        static let bounceCutoff: Double = 110
        static let rollFriction: Double = 850      // pt/s² against the ground
        /// Below this ground speed the buddy stops pretending to roll.
        static let restSpeed: Double = 26
        /// Floaters brake harder so a toss glides to a hover in a beat or two.
        static let floatDamping: Double = 1.4
    }

    /// Integrates one fixed step. `box` is the window size; `bounds` the
    /// rect origins are clamped into. `floats` turns gravity off for winged
    /// species: the toss glides to a mid-air stop instead of arcing down.
    /// Returns the new state plus what happened.
    static func step(
        _ s: State, dt: Double, box: CGSize, bounds: CGRect, floats: Bool = false
    ) -> (state: State, events: Events) {
        var st = s
        var events = Events()

        // Forces.
        if !floats {
            st.vy -= Constants.gravity * dt
        }
        let damping = floats ? Constants.floatDamping : Constants.linearDamping
        let keep = max(0, 1 - damping * dt)
        st.vx *= keep
        st.vy *= keep

        // Integrate.
        st.x += st.vx * dt
        st.y += st.vy * dt

        let maxX = Double(bounds.maxX - box.width)
        let maxY = Double(bounds.maxY - box.height)

        // Walls.
        if st.x < Double(bounds.minX) {
            st.x = Double(bounds.minX)
            st.vx = abs(st.vx) * Constants.restitution
            events.hitWall = true
        } else if st.x > maxX {
            st.x = maxX
            st.vx = -abs(st.vx) * Constants.restitution
            events.hitWall = true
        }

        // Ceiling.
        if st.y > maxY, st.vy > 0 {
            st.y = maxY
            st.vy = -st.vy * Constants.restitution
            events.hitCeiling = true
        }

        // Floor: bounce, or collapse into a rolling skid.
        if st.y <= Double(bounds.minY), st.vy < 0 {
            st.y = Double(bounds.minY)
            if -st.vy > Constants.bounceCutoff {
                st.vy = -st.vy * Constants.restitution
                events.hitFloor = true
            } else {
                st.vy = 0
            }
        }

        // Floaters rest wherever the glide runs out — mid-air included.
        if floats {
            if st.vx * st.vx + st.vy * st.vy < Constants.restSpeed * Constants.restSpeed {
                st.vx = 0
                st.vy = 0
                events.landed = true
            }
            return (st, events)
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
