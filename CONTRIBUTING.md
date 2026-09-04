# Contributing to Croissaint

Thanks for the interest. This project aims to stay small, native and readable.

## License for contributions

Unless it is stated otherwise, contributions to this repository are accepted
under GPL-3.0-or-later.

## Getting started

```sh
git clone https://github.com/chuahchengxi/croissant.git
cd croissant
./build.sh                         # build and assemble the bundle
./build/Croissaint --selftest       # quick health check (SELFTEST OK)
./build.sh --install               # install into /Applications and launch
```

You need macOS 14 or newer, Apple Silicon and the Xcode Command Line Tools. The
build is a plain `swiftc` invocation, see `build.sh`, with no Xcode project and
no external dependencies, reproducible by design. `Package.swift` is there so
SwiftPM aware editors can index the code.

Hitting a build or permission snag while developing? See the
[troubleshooting guide](docs/TROUBLESHOOTING.md).

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

## Reporting bugs and requesting features

You do not need to write code to help. Use the issue forms on the
[new issue](https://github.com/chuahchengxi/croissant/issues/new/choose) page.

- **Bug report.** Include your Croissaint version from Settings under About and
  your macOS version, plus clear steps to reproduce. The
  [troubleshooting guide](docs/TROUBLESHOOTING.md) explains what makes a report
  useful.
- **Feature request.** Describe the problem you are trying to solve rather than
  only a specific solution.

For general help and every support channel, see [support](SUPPORT.md).

## Pull requests

1. One topic per PR, with a clear description of the behavior before and after.
2. `./build.sh` must finish without warnings and `--selftest` must pass.
3. New user facing text must land in **every** supported language, since the
   build will not compile until it does.
4. Match the style of the file you are editing.

## Releases (maintainers)

```sh
git tag v2.1.0 && git push origin v2.1.0
```

A version tag starts the release workflow, which checks the version, builds,
applies the configured signing/notarization policy and publishes the DMG.
Configure tag protection and secret access in the repository's GitHub settings.
