# iPhone port status

Development beta, 25 October 2026. Target: iPhone 13, iOS 26+; the intended phone runs iOS 27.

## Verified

- Device and simulator SwiftUI builds pass Xcode compilation, including the linked Rust YouTube core.
- The native core builds for arm64 iPhone and simulator; Linux Clippy passes with warnings denied.
- Manual native-boundary calls returned live YouTube search results, AAC stream URLs and lyrics.
- A full AAC range transfer on Linux returned the expected byte count.
- IPA packaging validates arm64 iPhoneOS, minimum OS and archive contents.
- Native navigation light/dark/large-text screenshots were inspected. Empty accessory and large-text overflow fixes were confirmed.

## Integrated runtime results

Run 40211864427 passed compilation, launched the iPhone 13/iOS 26.5 simulator and returned live
YouTube search/artwork. Streaming and download resolution failed with the provider's
sign-in-required response. This is an observed runtime failure, not a passing playback check.
The same video resolved and served AAC bytes from Linux. Network/account differences must be
resolved; no network-verification bypass or proxy has been added.

An initial account verification, ephemeral sign-in window, desktop-compatible session import,
Keychain persistence and sign-out implementation is now in source. It has not been accepted
with a real account. Cookie renewal, account/page selection and proof-of-origin support remain
open; a cookie verification result alone cannot establish complete authenticated playback.

## Remaining release gates

- Live search, full download, downloaded playback and relaunch in the simulator.
- Physical iPhone import, streaming, background/lock-screen playback, airplane-mode cold launch,
  interrupted transfer recovery, network changes, accessibility and long listening sessions.
- Complete and validate account sign-in/library, playlist mutations, other providers, scrobbling and equalizer.
- Complete the desktop parity inventory in PARITY.md before a final IPA handoff.

The app is a development beta, not a feature-complete replacement for the desktop app.

## Repair batch 49c5a68b (26 October 2026)

Home shelf/genre, album/artist/playlist, account-library and lyrics response shapes now match the
Swift decoder requirements. Local live checks returned populated Home and detail payloads with
none of the previously missing required fields. Native Rust build/Clippy and Swift syntax checks pass.
The player has bounded background geometry, available-space artwork sizing, larger touch regions,
accessibility scrolling and reduced-motion/transparency handling. Metadata review uses a real public
YouTube search result, without fabricated playback or exported audio. Version is 0.3.0 (4).

Apple run 40231715841 compiled both targets and verified populated Home (8 sections, 90 items,
40 genres) and decoded synced lyrics (37 lines) on the iPhone 13/iOS 26.5 simulator. Artwork, lyrics,
queue and large-text captures were inspected. The fixed guest test video was refused with a
sign-in-required response, so streaming/download acceptance still failed. The confirmation batch
fixes the yt3 artwork-host case and accessibility control sizing, and probes several actual search
candidates to distinguish a gated track from general guest failure. Guest playback remains an
acceptance gate. Commercial Safari/OAuth sign-in is not implemented; see References/AppleMusic/AUTHENTICATION.md.
The user selected Emil Kowalski's apple-design skill instead of Impeccable.
