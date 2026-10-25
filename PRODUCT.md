# Sonora for iPhone

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

The owner of this checkout, listening on an iPhone 13 and developing on Linux.

## Product Purpose

Port Sonora to an iPhone app with reliable playback, offline downloads, library browsing,
search, queues and lyrics. YouTube Music is the first streaming provider requested.

## Operating Context

Develop on Linux. Compile with Xcode on a hosted macOS runner. Deliver an unsigned IPA for
the user to sign and install with iLoader. No paid developer membership is assumed.

## Capabilities and Constraints

- Native Liquid Glass requires iOS 26 or later; the user's iPhone 13 runs iOS 27.
- The desktop app is Rust/GPUI, not an existing iOS application.
- Provider parity is a goal, not an established capability of this port.
- A hosted build and real-device tests are required before calling an IPA verified.
- Retain upstream attribution and GPL-3.0-or-later licensing.

## Brand Commitments

Keep Sonora's name and existing icon. The user explicitly requests Apple's native pill-shaped
bottom navigation and Liquid Glass buttons. Platform behavior governs layout and interaction.

## Evidence on Hand

Desktop source, localization resources, icon assets, download queue, encrypted vault,
YouTube provider and the pinned ytmusic-rs dependency. Initial device and simulator builds and
native iPhone 13 screenshots now exist. Guest provider search/stream resolution and full-range
transfer have been verified on Linux. Integrated playback/download checks are in progress.

## Open Decisions

Physical-device installation/playback results and account sign-in behavior remain unverified.
The authorized GitHub fork is https://github.com/icesaviour02-droid/sonora.
