# Contributing to Croissaint

Croissaint aims to stay small, native and readable. Contributions are accepted
under GPL-3.0-or-later unless stated otherwise.

## Getting started

You need macOS 14 or newer, Apple Silicon and the Xcode Command Line Tools.
The project builds with `build.sh`, without an Xcode project or external package
dependencies. `Package.swift` supports editor indexing; it does not assemble or
sign the app bundle.

```sh
git clone https://github.com/chuahchengxi/croissant.git
cd croissant
./build.sh --dev
./build/CroissaintDeveloper --selftest
./build.sh --test
```

To install and launch the separate Developer app, use `./build.sh --dev --install`.
It has its own preferences and permissions and does not replace the official app.
A plain `./build.sh` builds the optimized variant used by CI; its health check is
`./build/Croissaint --selftest`.

### Stable signing (required once)

`build.sh` refuses to build until it can find a signing identity. That is
deliberate. An ad hoc signature's designated requirement is the binary's own
code hash, so it changes on every build and every permission you granted goes
stale with it — macOS keeps showing a ticked box in Accessibility while the app
sees `AXIsProcessTrusted()` as false, which reads as a bug in the app rather
than a signing problem. Developer builds (`--dev`) create a local identity if
none is available; plain builds ask you to run this once:

```sh
./Tools/setup-signing.sh
```

Either way `build.sh` then signs local builds with it and gives them a
constant designated requirement, so granted permissions stick across rebuilds.
If a permission was granted to an earlier ad-hoc build, clear the stale grant
once (`tccutil reset Accessibility com.croissaint.utils.dev`) and grant it
again. The identity is a local convenience only and never shows up outside
the keychain.

If you already ran that and the build still refuses, the login keychain is
probably locked — `security find-identity` returns nothing either way, which is
exactly why the script cannot tell the two apart and stops instead of guessing:

```sh
security unlock-keychain ~/Library/Keychains/login.keychain-db
```

`./build.sh --allow-adhoc` builds without an identity anyway. Use it for a
throwaway build or on CI, not for anything you plan to grant permissions to.

Released versions 0.1.5 and 0.1.6 were ad-hoc signed. Future release builds use
`SIGNING_CERT_P12` (base64 PKCS#12) and `SIGNING_CERT_PASSWORD` when configured;
otherwise they explicitly build ad-hoc. Partial or unusable credentials fail
the release instead of silently changing its identity. Reuse the same private
key across releases. A local self-signed identity preserves identity between
builds but does not make a download trusted by Gatekeeper.

For Apple notarization, supply a **Developer ID Application** certificate and
all three secrets: `NOTARY_API_KEY_P8` (base64), `NOTARY_KEY_ID`, and
`NOTARY_ISSUER_ID`. Apple Development and self-signed certificates cannot be
notarized. The workflow verifies and staples the app before packaging, then
notarizes and validates the DMG. Keep these credentials in GitHub secrets,
never in the repository. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Project layout

| Folder | Role |
|---|---|
| `Sources/Croissaint/App` | App lifecycle and the menu bar status item |
| `Sources/Croissaint/Core` | Localization, permissions, UserDefaults keys |
| `Sources/Croissaint/Services` | All behavior, like energy, monitor, scroll and switcher |
| `Sources/Croissaint/UI` | SwiftUI views only, no business logic |
| `Sources/Croissaint/Support` | `--selftest` and `--sensors` diagnostics |
| `Tools` | Icon generator and DMG packaging |

A few conventions to keep in mind.

- **UI observes services, and services never import SwiftUI.** Keep that boundary.
- Singletons are exposed as `Type.shared` and publish state with Combine through
  `ObservableObject`, with no Observation macros, since the project builds with
  the Command Line Tools.
- Comments explain *why*, not *what*. Keep them rare and useful.
- No new dependencies without talking it over first in an issue.

## Strings and translations

Every user facing string lives in `Core/Localization.swift` as a field of the
`Strings` struct. Adding a field forces **every** supported language to provide
it, and the compiler is the completeness check, so a translation can never
silently fall out of sync.

Croissaint ships eight languages today, namely English, Português (Brasil),
Español, Deutsch, Français, Italiano, 日本語 and 简体中文. The non base
translations live in `Core/Localizations/`. To add a language, add a case to
`AppLanguage` and a `static let` extension of `Strings` with every field
translated.

## Sensors on new chips

Temperature mapping lives in `SystemMonitor.prepareSensorsIfNeeded()`. CPU keys
look like `Tp…` and `Te…`, GPU is `Tg…`, and battery runs from `TB0T` to
`TB2T`. If a new Apple Silicon generation renames the keys, run this

```sh
./build/Croissaint --sensors
```

and open a PR with the dump and the adjusted prefixes.

Explain the behavior before and after, the scope and validation. Use
`type(scope): lowercase imperative phrase` for the title and reuse an existing
scope where possible. Open unfinished work as a draft and name what is missing.
The [template](.github/PULL_REQUEST_TEMPLATE.md) is a prompt, not a form.

Leave version bumps and `CHANGELOG.md` to the maintainer. Describe the user-visible
effect in the PR so it can become a release note with your credit.

When an issue exists, include one reference per line:

```text
Refs #123
Refs #456
```

Avoid `Closes` or `Fixes`: those close the issue at merge, before users receive
the fix. The fix-status workflow tracks the reference, notifies the reporter when
a stable release carries the fix, and can close the issue after two weeks without
a response. If the PR addresses only part of an issue, say exactly which part.

1. One topic per PR, with a clear description of the behavior before and after.
2. `./build.sh` must finish without warnings and `--selftest` must pass.
3. New user facing text must land in **every** supported language, since the
   build will not compile until it does.
4. Match the style of the file you are editing.

## Releases (maintainers)

Integrating into `main`, pushing a branch and opening a PR do not publish a release.
Publication requires an explicit release decision, including beta or stable.

Before sending a version tag, validate the final commit on `main`, confirm its
verified signature, and match `Resources/Info.plist` and the release notes to the
chosen version. Use a signed tag such as `vX.Y.Z-beta.N` or `vX.Y.Z`.
Sending the tag starts [the release workflow](.github/workflows/release.yml).

A version tag starts the release workflow, which checks the version, builds,
applies the configured signing/notarization policy and publishes the DMG.
Configure tag protection and secret access in the repository's GitHub settings.
