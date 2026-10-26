# Desktop parity and release gates

This is the acceptance checklist for the requested iPhone port. A successful IPA build is not
feature acceptance. Final releases remain gated; a user-requested development snapshot can be
provided with explicit limitations and source/build metadata. The target phone is iPhone 13, reported iOS 27.

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
| Guest YouTube song search, metadata/artwork | Catalog response repair verified on Linux and iOS 26.5 simulator | Empty/error/retry, Unicode, long results, unavailable songs; repeat on iOS 27 |
| YouTube AAC streaming | Implemented; latest simulator resolution blocked by Google's bot-verification response | Audible playback, advancing clock, pause/resume, long tracks, network/error recovery |
| Offline downloads | Implemented; latest simulator cannot resolve Guest audio | Exact byte count, playable file, progress, cancel/retry/remove, queued concurrency, interrupted recovery |
| Offline relaunch | Implemented file selection; unverified | Cold launch in airplane mode, play/seek/queue downloaded tracks without provider requests |
| Local audio import/search/delete | Generated WAV import, duration, advancing playback, pause, seek/resume and deletion verified in iOS 26.5 simulator | Other supported formats, corrupt files, large/multiple imports, durable metadata and local search |
| Queue, next/previous, shuffle, repeat, seek | Implemented subset; unverified | Order changes, boundaries, repeated tracks, unavailable tracks, restore without autoplay |
| Queue editing, play-next/append, radio/autoplay | Eight repeated-entry/order/restore checks verified in iOS simulator; native queue UI rendered and inspected | Touch-driven reorder/removal, radio continuation and queue persistence across actual relaunch |
| Background audio, lock-screen commands, AirPlay | Implemented; unverified on hardware | Screen lock, long background session, headphones/Bluetooth, calls/interruption, route loss |
| Gapless playback | Missing | Consecutive tracks with measured gap behavior |
| Audio normalization, quality selection | Implemented; runtime unverified | Provider loudness handling, level consistency, supported quality fallback |
| Equalizer/output options | Exact desktop DSP reused; six filter tests and generated-PCM C boundary pass on Linux and Apple host; native tap processes actual simulator audio; seven profile edit/import/export/restore checks pass | Native tap processing, presets/tone/manual and auto headroom, touch-driven parametric editing, physical audio routes and device rules |
| Sleep timer | Implemented; runtime unverified | Timed stop and end-of-track behavior across backgrounding |
| YouTube account sign-in/session/sign-out | Cookie sessions, renewal/page selection/proof-of-origin implemented but unaccepted; system Safari/OAuth missing | Real account login, Keychain storage, expiration/restore, sign-out cache isolation |
| Home feed, recommendations, genres | Populated Home verified on iOS 26.5 simulator; account personalization and genre navigation unverified | Loaded/empty/error/continuation and navigation behavior |
| Albums, artists/discography, song/user pages | Album/artist details implemented; broader desktop pages incomplete | Metadata, tracks, artwork, playback, navigation and errors |
| Search albums/playlists | Implemented; repaired live Linux catalog returns all four collection types | Simulator decoding, results/navigation, paging/error handling |
| Saved songs/albums/artists, likes/follows | Implemented; real-account acceptance missing | Read/write/undo/refresh, account isolation and persistence |
| Playlists | Implemented subset; creation currently private/title-only, full parity unverified | List/detail/paging, create/rename/delete/visibility, save/remove, add/remove tracks |
| Listening history/play counts, provider reporting | Local history implemented; provider reporting incomplete/unverified | Start/pause/seek/stop reporting and completed-listen rules |
| Pins/favorites and sharing/deep links | Implemented subset; runtime acceptance missing | Pin persistence, share destinations, malformed links and account changes |
| Plain YouTube lyrics | Implemented; Swift supports nullable timing fields | Correct track, loading/empty/retry, cancellation and provider attribution |
| Synced/karaoke lyrics, background vocals, romanization | 53 shared tests pass on Linux/Apple; simulator decodes 38 lines, 203 timed words and three source choices; nine native import/cache/source checks pass; actual timed playback interaction pending | Playback timing/seek synchronization, alternate sources/languages and fallback |
| LastFM/ListenBrainz/LibreFM/Maloja scrobbling | ListenBrainz/Maloja payloads, now-playing, earned thresholds and durable account-isolated retries pass sixteen Apple checks with an injected transport; real service delivery and LastFM/LibreFM linking missing | Auth, now-playing, completed listens, offline retry and duplicate prevention |
| Apple Music/Spotify/Deezer/Tidal/Subsonic/Navidrome | Missing | Each provider's supported sign-in, catalog, playback, library and download capabilities |
| Local albums/artists/playlists, folders/tag editing | Tagged albums/artists exist; native local playlists/favorites now reuse desktop SQLite, with sixteen Linux boundary checks passing; Swift CRUD/reorder/relaunch checks pending; folders/tag editing missing | Files security scope, metadata editing, indexes and rescan behavior |
| Appearance/fonts/icons/themes/layout customization | Native SF Pro Rounded/Inter selection, registration and relaunch verified in simulator; custom imports and artwork accents implemented; fuller customization missing | Import/remove/preview and persistence, Dynamic Type across screens, theme contrast, motion and desktop option inventory |
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
