# Desktop parity and release gates

This is the acceptance checklist for the requested iPhone port. A successful IPA build is not
feature acceptance. Test IPAs remain internal until these gates pass; previous beta links are
not a release recommendation. The target phone is iPhone 13, reported iOS 27.

Sources: README.md Features, crates/music/src/lib.rs MusicApi/Capabilities,
crates/router/src/lib.rs Destination/SettingsPage, and crates/state/src/.
The original application is a Rust/GPUI desktop client; this checkout does not supply a web app
whose behavior can be used as a separate reference.

## Status meanings

- Verified: an observed runtime result with evidence; the environment is stated explicitly.
- Implemented: source exists, but the required behavior is not accepted yet.
- Missing: no corresponding iPhone implementation.
- Platform review: desktop behavior needs an iOS equivalent or a documented platform limitation;
  it cannot silently be removed from the requested scope.

## Feature inventory

| Desktop behavior | iPhone status | Required acceptance |
|---|---|---|
| Guest YouTube song search, metadata/artwork | Verified in iOS 26.5 simulator | Empty/error/retry, Unicode, long results, unavailable songs; repeat on iOS 27 |
| YouTube AAC streaming | Implemented; simulator playback advancement failed | Audible playback, advancing clock, pause/resume, long tracks, network/error recovery |
| Offline downloads | Implemented; simulator resolution failed (sign-in required) | Exact byte count, playable file, progress, cancel/retry/remove, queued concurrency, interrupted recovery |
| Offline relaunch | Implemented file selection; unverified | Cold launch in airplane mode, play/seek/queue downloaded tracks without provider requests |
| Local audio import/search/delete | Implemented; unverified | Supported formats, corrupt files, large/multiple imports, durable metadata, deletion during playback |
| Queue, next/previous, shuffle, repeat, seek | Implemented subset; unverified | Order changes, boundaries, repeated tracks, unavailable tracks, restore without autoplay |
| Queue editing, play-next/append, radio/autoplay | Missing | Reorder/remove/append, radio continuation and queue persistence |
| Background audio, lock-screen commands, AirPlay | Implemented; unverified on hardware | Screen lock, long background session, headphones/Bluetooth, calls/interruption, route loss |
| Gapless playback | Missing | Consecutive tracks with measured gap behavior |
| Audio normalization, quality selection | Missing | Provider loudness handling, level consistency, supported quality fallback |
| Equalizer/output options | Missing / platform review | iOS audio-engine support and persistent sound settings |
| Sleep timer | Missing | Timed stop and end-of-track behavior across backgrounding |
| YouTube account sign-in/session/sign-out | Initial implementation; real-account verification, renewal/page selection/proof-of-origin remain open | Real account login, Keychain storage, expiration/restore, sign-out cache isolation |
| Home feed, recommendations, genres | Missing | Loaded/empty/error/continuation and navigation behavior |
| Albums, artists/discography, song/user pages | Missing | Metadata, tracks, artwork, playback, navigation and errors |
| Search albums/playlists | Missing | Results and navigation with paging/error handling |
| Saved songs/albums/artists, likes/follows | Missing | Read/write/undo/refresh, account isolation and persistence |
| Playlists | Missing | List/detail/paging, create/rename/delete/visibility, save/remove, add/remove tracks |
| Listening history/play counts, provider reporting | Missing | Start/pause/seek/stop reporting and completed-listen rules |
| Pins/favorites and sharing/deep links | Partial deep-link routes only | Pin persistence, share destinations, malformed links and account changes |
| Plain YouTube lyrics | Implemented; native Linux request verified | Correct track, loading/empty/retry, cancellation and provider attribution |
| Synced/karaoke lyrics, background vocals, romanization | Missing | Timing/seek synchronization, alternate sources/languages and fallback |
| LastFM/ListenBrainz/LibreFM/Maloja scrobbling | Missing | Auth, now-playing, completed listens, offline retry and duplicate prevention |
| Apple Music/Spotify/Deezer/Tidal/Subsonic/Navidrome | Missing | Each provider's supported sign-in, catalog, playback, library and download capabilities |
| Local albums/artists/playlists, folders/tag editing | Missing / platform review | Files security scope, metadata editing, indexes and rescan behavior |
| Appearance/fonts/icons/themes/layout customization | Missing beyond native light/dark | iPhone-safe equivalents with persistent settings |
| Storage/cache management | Partial download removal only | Usage counts, clearing, low storage, damaged indexes and interrupted writes |
| Localization/accessibility | English native strings; initial visual review verified | VoiceOver, large text across populated screens, contrast, reduced motion/transparency |
| Discord Rich Presence/tray/dock/MPRIS/window/fullscreen | Platform review | Document iOS-supported equivalents; desktop IPC/window features cannot be assumed portable |
| Updates and sideload lifecycle | Build packaging verified | Install/upgrade preserving data, launch on real phone, signing/provisioning behavior |

Provider parity means supported capabilities of each original provider, not invented guarantees
that every provider supports identical downloads or account mutations. Protected playback must
use a supported iOS path; the repository's rule forbids bundling a Widevine CDM.

## Required checks before calling an IPA final

1. Pass live simulator search, streaming clock advancement, complete download and downloaded playback.
2. Complete the missing mobile behaviors above and exercise their success, empty and failure paths.
3. Verify on an actual iPhone 13 running iOS 27: install/upgrade, audible playback, background/lock
   screen, network changes, airplane-mode relaunch and interrupted transfer recovery.
4. Check accessibility, long sessions, memory/thermal behavior, low storage, expired credentials,
   queue consistency and account switching. Record the build and evidence for each result.
5. Produce a release report listing passed checks and any unresolved feature or platform gap.
   An unresolved requested feature means full desktop parity has not been achieved.

No current IPA satisfies all these gates. Physical audio, signing and lifecycle behavior cannot
be certified from this Linux host or from screenshots alone.
