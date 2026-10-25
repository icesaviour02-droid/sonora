# Sonora for iPhone — initial development milestone

This directory starts the native iPhone port. **It is not the completed YouTube Music port.**
The deployment target is iOS 26.0 and the device family is iPhone, including iPhone 13.

## First cloud build

The iPhone device and simulator targets compiled successfully with Xcode in
[build 40191763029](https://github.com/icesaviour02-droid/sonora/actions/runs/40191763029).
An unsigned arm64 IPA was downloaded and its bundle/archive integrity verified locally.
That does not establish playback correctness on the physical iPhone.

## Implemented in the initial app

- Native SwiftUI Liquid Glass tab bar, mini-player accessory and player controls.
- Multi-file audio import through Files; durable library index; local search and deletion.
- AVPlayer queue, shuffle/repeat, seeking and background audio configuration.
- Lock-screen commands, interruption/route-change handling and playback failure reporting.
- Saved library and last queue; playback never starts automatically on launch.
- Native settings and downloads screens with honest empty/incomplete states.
- An unsigned-device build workflow and simulator smoke checks/screenshot artifacts.

## Not implemented

YouTube sign-in, lyrics, playlists, scrobbling, equalizer and the other streaming providers.
Guest search, native AAC playback and background downloads are implemented but still require
the next integrated build and device checks. Existing Rust code remains the reference for the
remaining implementation.

The download queue persists metadata and iOS transfer identifiers, retries with freshly resolved
URLs, and verifies byte length and playability before marking a file complete. Completed files
stay inside the app sandbox with iOS data protection. Playback prefers those files, including
after an offline cold launch. Cellular downloads are off by default. iOS force-quit behavior and
provider URL expiration remain platform constraints; failed transfers can be retried in the app.

## Build an unsigned IPA without owning a Mac

1. Put this checkout, including the iOS changes, in a GitHub repository you control.
2. Open Actions → **iPhone IPA** → **Run workflow**.
3. Download the **Sonora-iPhone-unsigned** artifact after the build succeeds.
4. Extract `Sonora-unsigned.ipa`, then sign/install it using iLoader.

Standard macOS runners are free for public repositories. Artifacts have storage quotas, and this
workflow expires them after seven days. No Apple ID or certificate belongs in this repository.
Sideload signing is performed by the user's installation tool, not by this build.

The generated IPA is a device app, not a simulator app. A separate simulator build launches the
empty library and captures light/dark screenshots. Review those and test on the iPhone before
calling a build usable. A successful compile cannot establish playback/download correctness.

## Local preparation on Linux

`python3 ios/scripts/prepare.py` regenerates the Xcode project and iOS string resources from the
canonical English Fluent keys beginning with `ios-`. Do not edit generated files directly.

The iOS shell uses Apple's audio stack directly. `Core/` isolates the desktop YouTube client
behind a small native API. It compiles on Linux; a live anonymous search returned 20 results,
and stream resolution produced AAC audio with a successfully verified 1 MiB range. The app now
links the native core, offers YouTube/library search scopes and resolves streams just before
playback. Signed stream URLs are not saved to the queue. The earlier IPA remains local-only;
the next integrated build is required before delivering these capabilities.

The workflow builds both native libraries before invoking Xcode. On a Mac, use
`python3 ios/scripts/build_native.py` after installing the two iOS Rust targets. Do not attempt to
cross-compile the complete desktop workspace into the app.

## Milestones and planning estimates

These are rough engineering-effort estimates, not elapsed-time commitments or unattended work:

1. Foundation and first cloud/device build: 1–3 working days, including fixing build/device issues.
2. YouTube authentication, catalog and playback integration: 1–3 weeks, depending on protocol compatibility.
3. Reliable downloads, offline metadata, queue/library mutations and lyrics: another 2–4 weeks.
4. iPhone 13 performance, accessibility and failure/recovery testing: another 1–2 weeks.
5. Remaining provider parity: separate work; potentially months and provider-specific limitations.

Before milestone 2, validate the pinned ytmusic-rs client on iOS: its stream resolution, cookies,
proof-of-origin token acquisition and network lifecycle are critical dependencies. Resolve stream
authorization while foregrounded and determine whether transfer requests can be handed to Apple's
background session; do not assume a custom Tokio download survives suspension.

Release gates include real-device background playback, network switching, airplane-mode cold
launch, interrupted download recovery, low storage, expired auth/stream URLs, seek/queue behavior,
VoiceOver, large text, reduced transparency/motion and long listening sessions. Gapless playback
and equalizer parity need a dedicated engine decision; AVPlayer alone is not proof of parity.
