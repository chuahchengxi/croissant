# Trademarks

The source code in this repository is licensed under [GPL-3.0-or-later](LICENSE).
That license covers copyright in the source code. It does not cover names, logos
or branding, which is what this file is for. The two are separate grants, and
nothing here narrows the freedoms the GPL gives you over the code itself.

## Where Croissaint comes from

Croissaint is a fork of **Vorssaint** (originally released as *Vorssaint Utils*),
an open source macOS menu bar utility by **Vorssaint** — upstream at
<https://github.com/vorssaint/vorssaint-utils>, licensed GPL-3.0-or-later.

Effectively all of the architecture, and the great majority of the features this
app is useful for, were built upstream. The per-app volume mixer, App Switcher,
Command Bar, Shelf, Dock previews, clipboard history, system monitor, fan
control, the uninstaller and the rest of the utility set are upstream work.
Croissaint would not exist without it, and the credit for the foundation belongs
there.

That inheritance is not only the original author's. This repository's history
retains commits from **66 contributors** to the upstream project, and their
authorship is preserved in `git log` rather than squashed away. Upstream
copyright notices stay intact in the files that carry them.

Croissaint claims **no rights whatsoever** in the Vorssaint name, its logo, its
bundle identifiers or its signing identity. Those belong to the upstream
maintainer. This project is an independent fork: it is **not** endorsed by,
affiliated with, or supported by the Vorssaint project, and it must never be
presented as though it were. Bugs found here are this fork's problem and should
be reported here, never to upstream.

## The Croissaint marks

The name **Croissaint**, the croissant logo and menu bar glyph, the app icon and
in-app watermark generated from `Resources/Brand/logo.png`, the bundle
identifiers under `com.croissaint.*`, the update feed, and the code signing
identity *"Croissaint Utils Signing"* are unregistered marks of the project
maintainer, Chuah Cheng Xi (@chuahchengxi). No registration is claimed.

Official Croissaint builds are distributed only by the maintainer, through this
repository's GitHub releases and its Homebrew tap. Builds from anywhere else are
not Croissaint releases, however they are labelled.

## What the GPL does not grant

Receiving the source under the GPL does not grant permission to use the
Croissaint name, logo, icon, bundle identity, trade dress, official branding,
update feed, or any signing identity controlled by the maintainer.

In particular, do not:

- present a modified build as Croissaint, or as an official release;
- ship a binary under the Croissaint name, icon or bundle identifier;
- reuse the `com.croissaint.*` identifier space, which also keys the app's TCC
  permissions and preferences domain — reusing it silently inherits grants a
  user gave to a different application;
- reuse or attempt to reproduce the signing identity, or imply a build was
  signed by the maintainer;
- point a rebuild at this project's update feed;
- use the marks in a way that suggests endorsement, affiliation or official
  status that does not exist.

## If you fork Croissaint

You are welcome to — the GPL guarantees it, and this project is itself a fork.
Do for this project what it does for upstream: pick your own name, your own app
icon, your own bundle identifier, your own signing identity and your own update
feed, and say plainly in your README what you forked from and what you changed.

That is what happened here. Croissaint took a new name, a new mark, a new
`com.croissaint.*` identifier space, its own signing identity and its own update
feed, and removed the upstream project's branding rather than shipping under it.
The policy in this file asks of others exactly what this fork already did.

## What is always fine

This policy targets misrepresentation, not conversation. Without asking anyone,
you may:

- say truthfully that your software is a fork of, based on, or compatible with
  Croissaint, as long as your own name is what is on the product;
- name Croissaint in reviews, articles, comparisons, tutorials, videos and
  discussion;
- link here, and quote from the documentation with attribution;
- distribute unmodified official builds as you received them.

## Questions

Open an issue at <https://github.com/chuahchengxi/croissant/issues>. Permission
beyond the above is granted only in writing by the maintainer.
