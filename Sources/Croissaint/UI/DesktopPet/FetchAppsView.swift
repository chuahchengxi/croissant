// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The buddy's little party trick: type the name of an app, it fetches and
/// launches it. Reads the shared installed-apps list, so no separate scan of
/// /Applications ever runs for the pet's sake.
struct FetchAppsView: View {
    var onFetched: ((String) -> Void)?

    @EnvironmentObject private var pet: PetState
    @State private var query = ""
    @State private var apps: [InstalledApps.InstalledApp] = []

    private var results: [InstalledApps.InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = apps.filter { $0.name.lowercased().contains(q) }
        let sorted = matches.sorted {
            let aPrefix = $0.name.lowercased().hasPrefix(q)
            let bPrefix = $1.name.lowercased().hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            return $0.name.lowercased().count < $1.name.lowercased().count
        }
        return Array(sorted.prefix(5))
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Ask your pal to fetch an app...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                    .onSubmit { if let first = results.first { fetch(first) } }
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
            .onAppear { loadApps() }

            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                if results.isEmpty {
                    Text("No apps found — your pal tried its best!")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(results) { app in
                        row(app)
                    }
                }
            }
        }
    }

    private func loadApps() {
        DispatchQueue.global(qos: .utility).async {
            let found = InstalledApps.installedApplications(includeSystemApplications: true)
            DispatchQueue.main.async { apps = found }
        }
    }

    private func row(_ app: InstalledApps.InstalledApp) -> some View {
        Button {
            fetch(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(.system(size: 12, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.primary)
    }

    private func fetch(_ app: InstalledApps.InstalledApp) {
        if NSWorkspace.shared.open(app.url) {
            pet.rewardFetch()
            onFetched?(app.name)
            NotificationCenter.default.post(name: .pokePalCelebrate, object: nil)
            query = ""
        }
    }
}
