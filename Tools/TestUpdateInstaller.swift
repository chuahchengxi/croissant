// SPDX-License-Identifier: GPL-3.0-or-later
// End-to-end installer checks using disposable signed apps and a real DMG.
// swiftc Sources/Croissaint/Services/DetachedProcess.swift \
//   Sources/Croissaint/Services/Update/UpdateInstallerSupport.swift \
//   Tools/TestUpdateInstaller.swift -o /tmp/croissaint-installer-tests
import Foundation

@main
enum TestUpdateInstaller {
    static func check(_ condition: Bool) { precondition(condition) }
    static func main() throws {
        precondition(UpdateInstallerSupport.installerScript().contains(
            "/bin/launchctl asuser \"$ASUSER\" /usr/bin/sudo -n -u \"#$ASUSER\" /usr/bin/open"))
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Croissaint updater's test-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        @discardableResult
        func run(_ command: String, _ args: [String]) throws -> Int32 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: command)
            task.arguments = args
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        }
        let payload = root.appendingPathComponent("payload")
        let source = payload.appendingPathComponent("Croissaint.app")
        let contents = source.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: contents.appendingPathComponent("MacOS/Croissaint").path)
        let plist: [String: String] = [
            "CFBundleIdentifier": "com.croissaint.utils",
            "CFBundleExecutable": "Croissaint",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.7",
            "CFBundleVersion": "90"
        ]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        check(try run("/usr/bin/codesign", ["--force", "--sign", "-", source.path]) == 0)
        let image = root.appendingPathComponent("release.dmg")
        check(try run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", payload.path,
                                                "-format", "UDZO", image.path]) == 0)
        try Data("tampered".utf8).write(to: contents.appendingPathComponent("MacOS/Croissaint"))
        let tamperedImage = root.appendingPathComponent("tampered.dmg")
        check(try run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", payload.path,
                                          "-format", "UDZO", tamperedImage.path]) == 0)

        func install(_ name: String, expectedVersion: String, damageImage: Bool = false,
                     damageSignature: Bool = false) throws {
            let folder = root.appendingPathComponent(name)
            let app = folder.appendingPathComponent("Croissaint.app")
            try fm.createDirectory(at: app, withIntermediateDirectories: true)
            let sentinel = app.appendingPathComponent("old-install")
            try Data("preserve me".utf8).write(to: sentinel)
            let download = folder.appendingPathComponent("download.dmg")
            if damageImage {
                try Data("not a disk image".utf8).write(to: download)
            } else {
                try fm.copyItem(at: damageSignature ? tamperedImage : image, to: download)
            }
            let script = folder.appendingPathComponent("installer.sh")
            // Exercise the production script, without launching any GUI app.
            try UpdateInstallerSupport.installerScript()
                .replacingOccurrences(of: "/usr/bin/open", with: "/usr/bin/true")
                .write(to: script, atomically: true, encoding: .utf8)
            let marker = folder.appendingPathComponent("result")
            let exited = try run("/bin/sh", [script.path, app.path, download.path, "2147483647",
                                            marker.path, "\(getuid())", expectedVersion])
            let result = try String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            if damageImage {
                precondition(exited != 0 && result == "fail-dmg-verify" && fm.fileExists(atPath: sentinel.path))
            } else if damageSignature {
                precondition(result == "fail-verify" && fm.fileExists(atPath: sentinel.path))
            } else if expectedVersion == "0.1.7" {
                precondition(result == "ok" && !fm.fileExists(atPath: sentinel.path))
                check(try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0)
            } else {
                precondition(result == "fail-version" && fm.fileExists(atPath: sentinel.path))
            }
            precondition(!fm.fileExists(atPath: download.path) && !fm.fileExists(atPath: script.path))
            check(try fm.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.contains(".update-") })
            print("PASS: \(name)")
        }
        try install("successful swap", expectedVersion: "0.1.7")
        try install("wrong version preserves old app", expectedVersion: "0.1.8")
        try install("invalid signature preserves old app", expectedVersion: "0.1.7", damageSignature: true)
        try install("invalid DMG preserves old app", expectedVersion: "0.1.7", damageImage: true)
    }
}
