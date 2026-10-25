# iPhone port status

Development beta, 25 October 2026. Target: iPhone 13, iOS 26+; the intended phone runs iOS 27.

## Verified

- Device and simulator SwiftUI builds pass Xcode compilation, including the linked Rust YouTube core.
- The native core builds for arm64 iPhone and simulator; Linux Clippy passes with warnings denied.
- Manual native-boundary calls returned live YouTube search results, AAC stream URLs and lyrics.
- A full AAC range transfer on Linux returned the expected byte count.
- IPA packaging validates arm64 iPhoneOS, minimum OS and archive contents.
- Native navigation light/dark/large-text screenshots were inspected. Empty accessory and large-text overflow fixes were confirmed.

## Integration check in progress

Run 40208633614 compiled the app and packaged an IPA, but the live simulator check timed out.
Review screenshots show SpringBoard's external URL confirmation prevented the search/download
routes from reaching the app. The debug runner now passes the same validated routes at launch,
avoiding that prompt. This correction and the latest download safeguards require a new run.
No successful integrated download or playback check is claimed yet.

## Remaining release gates

- Live search, full download, downloaded playback and relaunch in the simulator.
- Physical iPhone import, streaming, background/lock-screen playback, airplane-mode cold launch,
  interrupted transfer recovery, network changes, accessibility and long listening sessions.
- YouTube sign-in/account library, playlist mutations, other providers, scrobbling and equalizer.

The app is a development beta, not a feature-complete replacement for the desktop app.
