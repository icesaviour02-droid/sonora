# iPhone port status

Development beta, 26 October 2026. Target: iPhone 13, iOS 26+; the intended phone runs iOS 27.

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

Account verification, ephemeral sign-in, desktop-compatible session import, Keychain persistence,
account/page selection, cookie renewal and proof-of-origin support are in source. They have not
been accepted with a real account; a cookie verification result alone cannot establish complete
authenticated playback. The requested system Safari sign-in is still unimplemented.

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

## Desktop-path confirmation 7c3aa2f2 (26 October 2026)

Apple run 40234634963 compiled device and simulator targets. Actual simulator Home returned
8 sections, 79 items and 40 genres; synced lyrics returned 37 decoded lines. The 01f5a62b captures
confirm that the yt3 display-sized artwork is sharp and large-text player controls no longer overlap.
These captures review metadata/layout; they do not establish working audio.

All four live search candidates failed Guest resolution with `network_verification_required`.
Sanitized provider diagnostics confirm Google's bot-verification response and LOGIN_REQUIRED,
without a decipher or audio-host refusal. No PO token stage was reached. This happens with
the same `open_audio_within` method used by desktop; changing the one-byte check was insufficient.
Linux resolved a public test track through that method, but this is not an iPhone playback pass.
The user also confirms that the older installed IPA requires sign-in when playing Search results;
the precise server response on their phone has not been captured.

The subsequent Search repair restores the catalog's `songs` field (Library continues to use
`liked_songs`). A live Linux boundary check returned 20 songs, albums, playlists and artists each.
Simulator acceptance now requires decoded Search results as well as Home/lyrics, real advancing
stream playback, complete download and advancing downloaded playback. IPA upload is after these
checks; a missing repository variable cannot silently skip the audio check. A failing build must
not be handed off as a working IPA. Authenticated playback, physical-device behavior and the
remaining feature inventory are still release gates.

## Font and appearance work (26 October 2026)

The full desktop feature goal remains active. The previous goal work made progress: it changed
source and produced simulator evidence, rather than only waiting. A two-hour heartbeat is active
to resume this same goal when possible; no account limit reset time is guaranteed.

The font system now supports native SF Pro Rounded, bundled Inter faces and user-imported
TTF/OTF/TTC files, with persistence, Dynamic Type text styles and removal of imported collections.
No separately supplied SF Pro Rounded file is currently in the project root. iOS supplies its
rounded system design without redistributing Apple's desktop font files. Shared text styles
across screens now resolve the user's font choice. Native system navigation keeps system styling.
Appearance also supports artwork-derived contrast-adjusted accent colors and named system accents.
Simulator checks for font registration, selection persistence and screenshots are added; their
Apple compilation/runtime result is pending. This does not resolve Guest audio verification.
