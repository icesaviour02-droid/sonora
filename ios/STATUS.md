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
Apple results are recorded below. This does not resolve Guest audio verification.

Apple run 40255941831 compiled device and simulator targets and passed font availability,
selection and relaunch checks for SF Pro Rounded and Inter (5 registered faces). The two captured
font settings screens were visually inspected: the selected font changes the preview and body
text, with no clipping. The run subsequently failed at the already-known Guest verification gate.

## Queue and local-file repair batch (26 October 2026)

Queue occurrences now carry distinct UUIDs, so repeated songs can be selected/removed/reordered
individually. Playing Next uses a native List with reorder handles and removal, and only shows
upcoming entries. Queue snapshots retain entry identity, the selected occurrence, original order,
shuffle and repeat, with migration from old track-only snapshots. Clear Upcoming retains the past.
Debug simulator checks exercise repeated entries, moves, removal, shuffle, restore without autoplay
and repeat persistence. These checks still need Apple runtime acceptance.

Local-file lyrics no longer validate an app UUID as a YouTube ID. A live Linux boundary request
without any video ID returned 37 synced LRCLIB lines. Disabled local lookup now clears stale lyrics.
Imported local files retain album and duration metadata. A generated WAV simulator check now
exercises actual import, advancing playback, pause, seek/resume and deletion before attempting
network-dependent Guest audio. Source syntax and Rust Clippy/build checks pass; Apple results pending.
Apple run 40256955207 is the exact queue/local repair snapshot at da48eede and must be checked
before making further acceptance claims. Inspect queue-review.json, local-playback-review.json
and local-lyrics-review.json, plus the actual duplicate-entry queue screenshot. The goal remains active.

Run 40256955207 passed all eight queue occurrence/order/restore checks. Its generated WAV test
passed actual import, duration metadata, playback clock advancement, pause, seek/resume and deletion.
Local metadata-only lyrics decoded 37 synced lines in the simulator. The duplicate-entry queue
screen was visually inspected: both rows, removal controls and native reorder handles render correctly.
The run then failed on the same Guest network-verification gate; no IPA was published.

## Shared desktop equalizer integration (26 October 2026)

The mobile core now compiles the existing `crates/music/src/equalizer/` source directly, without
GPUI, rodio output or copied filter implementations. A C boundary exposes one preallocated reader
per AVFoundation audio tap; render processing does not allocate, lock or use Tokio. Configuration
runs on Tokio and has revision ordering so an obsolete slider request cannot replace newer settings.
The native player installs a MediaToolbox audio tap before starting playback. Presets use the
desktop's actual ten-band curves and tone shelves, with automatic headroom/manual preamp, smooth
changes and normalization capable of positive gain. Unsupported processing is reported explicitly.

All six existing desktop DSP tests pass in the isolated core. The generated-PCM C-boundary check
passes exact finite-sample bypass, matching planar/interleaved stereo, frequency-selective bass
response, preset headroom, APO parsing, stale-request rejection and +6 dB normalization. These are
Linux DSP results. iPhone device/simulator compilation and actual AVFoundation tap processing
remain pending; the local playback check now requires a positive native processed-frame count.
Full parametric editing, named profiles/device rules and APO import/export UI are still missing.

Apple native-core run 40259560019 passed, including the six reused filter tests, generated-PCM
C-boundary checks on the Mac host, and both iPhone/simulator static-library builds. iPhone run
40259560062 has compiled the device app and is checking simulator/runtime behavior for snapshot
0c4607bd. Re-poll that same run rather than restarting it. Its positive tap-frame assertion is the
required evidence for actual AVFoundation integration; compilation and core tests alone are insufficient.

Run 40259560062 completed. Its local-playback-review.json confirms seven passed checks, including
positive native audio-tap processing, real clock advancement, pause and seek/resume. The iOS DSP
bridge is therefore exercised through AVFoundation, not only compiled. The run again failed later
at Guest verification, and did not publish an IPA.

## Named profiles and parametric filters (26 October 2026)

Native Sound settings now have profile creation from desktop presets, selection, renaming,
deletion, up to 20 editable/reorderable filters with all eight desktop types, Q/octave widths,
frequency/gain/enable controls and per-profile automatic/manual preamp. Files import/export uses
the actual desktop Equalizer APO parser/exporter; unsupported lines are reported rather than hidden.
Descriptions validate drafts without changing playback. Profile JSON writes are atomic, corrupt
saved files are preserved, and the selected profile survives relaunch. Sound-specific device rules
are still missing, and touch interaction/Files-picker acceptance remains separate from store checks.

The extended generated-PCM check passes valid profile edits/round-trip, rejected invalid shelves
and filter counts, import warnings, unchanged audio during preview, and a frequency-selective notch.
Swift syntax and canonical localization checks pass. Apple compilation and a new native profile-store
acceptance sequence (create, validate/edit/save, export, import/warnings, reload and delete) are pending.

The user explicitly cancelled two-hour scheduling. Automation `continue-sonora-iphone-feature-parity`
has been deleted; the full goal remains active for continuous work in this chat. Do not recreate it.

## Profile acceptance and shared lyrics (26 October 2026)

Apple run 40262750069 at 1c371e24 compiled device and simulator targets. All seven native profile
checks passed (create, validate/edit/save, export, import, unsupported-line reporting, restoration,
delete). Both settings screenshots were inspected. Guest verification still failed; no final IPA
was published.

Lyrics now reuse the desktop's models, six remote sources, matching/ranking, LRC/TTML readers and
romanization, with an optional Local sidecar source. All 53 shared Rust tests pass on Linux, as do
Clippy and native boundary checks for enhanced LRC words, repeated stamps and TTML backing vocals.
A live LRCLIB lookup returned 37 synced lines. The native screen adds source enable/reordering,
alternate sheets, word highlighting against AVPlayer's clock, backing lanes, lyric text sizing,
import/copy/refresh, manual-scroll interruption and a follow-current-line action. Saved sheets and
imported sidecars are serialized off the UI thread and remain readable without network lookups.

Swift syntax passes. Apple compilation and the new eight-check native import/cache/source sequence
are pending; word-highlight motion and touch-driven interactions still require runtime review.
Per-script romanization controls, exact Apple Music highlight effects and actual phone acceptance
are not complete. No two-hour automation remains; the user requested continuous active work.

## Listening and durable submissions (26 October 2026)

The fifteen-second playhead trigger has been replaced with listening-time accounting. Pauses,
buffering, restore positions and seeks do not earn listens. Tracks under thirty seconds do not
count; other tracks require half their duration or four minutes. Each repeat/queue occurrence has
its own listen ID and original start timestamp. History begins when native output starts.

ListenBrainz now-playing and completed-listen payloads and Maloja artists/length/time fields now
match the desktop protocol. A per-service durable outbox keeps unsuccessful submissions, applies
backoff, isolates changed accounts by credential digest, and retries on foreground/relaunch.
Credentials remain in Keychain; queue files contain no tokens. The settings screen shows pending
listens and offers retry. These changes and sixteen native acceptance checks are pending Apple
compilation/runtime evidence. Last.fm/Libre.fm linking and real-account acceptance remain missing.

## Local covers, embedded lyrics and albums (26 October 2026)

Local import now reads embedded covers, album artist, disc/track numbers and lyric tags.
Covers are stored with relative filenames, orientation corrected and bounded to 1600 pixels;
the shared artwork component supports local files in rows, player, background, lock-screen and
artwork accent calculation. Removing an import removes its cover and imported lyric sidecar.
Embedded lyrics use the existing parser and remain readable without a network request.

Library Albums now includes imported records. Album-artist grouping keeps compilations together,
and disc/track tags order local album playback. Existing native song rows, artwork cards and play/
shuffle controls are reused. A generated AAC fixture with actual AVFoundation tags, synthetic cover
and self-authored timed lyrics extends local acceptance with metadata, cover/sidecar restoration,
album grouping/order and cleanup checks. Swift syntax passes; Apple runtime results are pending.

Apple run 40267418409 at c058f44a compiled both targets and passed all eight initial native lyrics
store checks. The actual remote sheet had 38 lines, 203 timed words and three source choices.
The lyrics screen was inspected; the source-options button is being tightened to a native circle,
and inactive/active line typography now has a stable size. Actual generated-WAV playback including
the native DSP still passed all seven checks. Shared core run 40267418289 passed Apple host tests,
boundary checks and both release libraries. Guest resolution alone still failed with verification
required. This is not final IPA acceptance.

## Native listening acceptance and response preview (26 October 2026)

Run 40268417184 at fdab598b compiled both Apple targets and passed all sixteen listening/outbox
checks. Downloaded scrobble-review.json confirms actual timestamp preservation, correct payloads,
per-service acknowledgement, durable backoff/relaunch, account isolation and secret-free storage.
The expanded lyrics store passed nine checks, including keeping imported lyrics when clearing cache.
Guest verification still failed; service account authentication and actual scrobble delivery are
not established by the injectable transport checks.

Run 40269539723 at 71bc1938 compiled local artwork/albums changes and reached only the remaining
Guest-resolution failure after the extended native tagged-audio acceptance sequence. The count-only
artifacts are being retrieved for direct inspection. Shared-core run 40269539628 also passed.

Sound-profile editors now preview a logarithmic frequency-response chart. Points and preamp come
from the exact desktop Curve response, including filter centre frequencies. A Linux boundary check
compares the graph at the test filter's centre to actual rendered PCM within 0.02 dB; it passes,
along with Clippy and Swift syntax. Previewing still leaves playing audio unchanged. Apple graph
compilation, rendering and accessibility review remain pending.

## Request cancellation and sound observation (26 October 2026)

Native requests now have bounded IDs and explicit cancellation. Canceling a Swift task signals the
Tokio work, drops the request future and still returns exactly one owned callback. Start/cancel are
ordered by a small lock outside the audio thread; duplicate IDs and more than 256 simultaneous
registered requests are rejected. Cancellation does not abandon checked continuations. A host C
stress check passed 256 pending cancellations, 100 completion races, normal completion, duplicate
rejection and zero registrations remaining. All 53 shared tests, existing boundary checks, Clippy
and Swift syntax still pass. Swift early/in-flight/normal cancellation acceptance is pending Apple.

The player-menu EQ toggle previously lacked a direct apply handler. Sound configuration is now
observed once at app scope, covering preset, bypass, preamp, tone, normalization and profile edits
regardless of which screen changed them. Duplicate per-screen apply handlers have been removed.
Three native observation/latest-configuration checks are included; Apple results remain pending.

Directly downloaded local-playback-review.json from run 40269539723 confirms fifteen passing
checks, including actual tagged AAC export/import, cover/metadata restoration, embedded lyrics,
compilation grouping/order, native processed frames, real clock/pause/seek and media/cover removal.
The fixture is self-generated audio, cover and lyric text. Local album touch navigation and physical
phone behavior are still outstanding.

## Simulator fixture isolation repair (26 October 2026)

Run 40284403208 passed Apple host cancellation stress, all shared tests and both production iOS
libraries. Run 40284403215 compiled both app targets, but its Swift cancellation probe failed at
normal/in-flight calls while early cancellation passed. Direct artifact inspection confirms this
pattern. The simulator links an optimized Rust archive, where debug assertions had removed the
new delayed QA operation. This is a test-build mismatch, not evidence of passing wrapper behavior.

An explicit review-fixtures feature now enables that deterministic operation only for the simulator
archive staged by build_native.py. The iPhoneOS IPA archive keeps the feature off. Host CI also tests
that an optimized production archive rejects the fixture and that optimized QA cancellation passes.
Swift wrapper and sound-observation acceptance must still be rerun. The prior response graph was
visually inspected; its deep notch drew below the plot into the caption. Plot clipping is included
in 422e1bdf and awaits the new screenshot capture.

## User-requested current development IPA (26 October 2026)

The user explicitly requested an IPA with all current changes in ios/build/LATEST-VERSION.
Manual workflow dispatch can now publish an explicitly labeled development snapshot after the real
arm64 iPhone build and package integrity checks, while simulator acceptance still runs. Ordinary
push builds and the final unsigned artifact retain the existing full acceptance gate. Development
snapshots do not establish feature completeness. Package metadata now records source commit,
workflow run, build kind/time, build number and SHA-256. This snapshot increments the build to 10.

## Verified build 10 device archive and local library work (26 October 2026)

The user's requested development IPA is saved, unchanged, in build/LATEST-VERSION as
Sonora-0.3.0-build10-aad9b1de.ipa (6,927,846 bytes; SHA-256
82b2f2e2f85cf332ab92124591df692b300c8bb7b6e383c7ce891967b9bc4208).
Source aad9b1de; manual run 40287973238. Local validation checked archive CRC, source/hash, version,
and the actual arm64 Mach-O iPhoneOS platform (2), excluding Simulator platform (7).
Direct a6a322db artifacts confirm all three Swift cancellation and all three live sound-observation
checks passed. The clipped response graph was visually inspected; its notch no longer crosses
the caption. Guest verification remains failed and the full goal is active. This development
snapshot was explicitly requested; it is not a feature-complete release.

Build 11 work adds native local playlists, track/album/artist favorites and local artist pages.
The backend compiles the exact desktop local Store and storage crate, including SQLite schema,
with shared local ID namespaces. Bulk create/add/remove/delete/reorder operations are transactional;
stale/duplicate reorders are rejected. Deleted imports are cleaned out of playlists/favorites.
Sixteen native-boundary checks pass on Linux, including SQLite trigger-induced failure rollback,
NUL/Unicode IDs, duplicate prevention and damaged-file preservation. All 53 existing shared tests
and Clippy pass. Native state owns serialized writes; native drag ordering updates immediately and
rolls back/refetches on save failure. Canonically equivalent favorite names use a normalized ID.

Library Playlists combines account-independent local playlists and the existing YouTube collection.
Creation, selection/search, editing, add/remove/reorder, favorites, album/artist navigation and
player actions reuse shared song/artwork components. Local bootstrap now runs before remote account
restoration and the root no longer disables all local controls while sign-in is pending. Home is
refreshed after account restoration. Physical airplane-mode startup remains unverified.
Thirteen Swift state checks and four actual app-relaunch checks, using real imported generated AAC
files and a review-only database, passed on the iPhone 13 simulator at 9cabc6ce (run 40297091255).
Build 10 remains frozen for the user; these new changes belong to the next build.

Known next authentication issue: pinned ytmusic-rs persist_cookies explicitly replaces freshly
supplied headers when its cookie file exists. The current authenticate builder always enables that
file, so an old saved store can shadow a new login. Account restore/renewal also needs reliable
Keychain persistence of rotated cookies. This has been confirmed by source inspection, not fixed
or accepted with a real account. System Safari Google OAuth remains unimplemented.

## Build 12 user-reported playback and interface changes (26 October 2026)

The user reports that every YouTube song on build 11 has twice its normal duration, with a
silent second half, both downloaded and streaming. Desktop playback works. A CLI-resolved AAC
reference file reports 266.773333 seconds in ffprobe at 44.1 kHz; the old bridge truncated it to
266 seconds. The iPhone periodic observer unconditionally replaced provider duration with item
duration. A new timeline policy preserves precise source duration, reads native audio-track extent,
and sets AVPlayerItem.forwardPlaybackEndTime for both streaming and completed downloads. Legacy
downloads lacking source duration correct only a clearly doubled container against catalog data;
no blind divide-by-two or silence detection is used. Actual user recording/hardware acceptance is
still needed; the exact native cause of the doubled duration has not been independently reproduced.

Native regression checks now cover duration policies, a real AAC item reaching its bounded end,
persisted download source duration, old JSON decoding and saved playlist order. Apple runtime
results are pending. Shared Rust tests (53) pass locally. No user download is deleted for migration.

The inline tab accessory hides Next while the expanded accessory retains it. Queue removes the
segmented selector and edit-mode delete circles, keeps native reorder handles and swipe deletion,
provides Add Songs multi-selection, and reveals history above Queue by scrolling. The official
Apple queue screenshot and behavior source are recorded in References/AppleMusic/sources.json.
Sonora has no working AutoMix/Crossfade implementation, so no inert control was added for it.

Downloads now separates active transfers from completed categories (songs/albums/artists/playlists),
adds song search/sorting and recent tiles, and keeps retry/cancel accessible. Downloading a whole
playlist saves a separate atomic manifest of its name, cover and song order; existing individually
downloaded songs are preserved but cannot retroactively recover playlist membership. Detail pages
show only completed songs. Playlist, downloaded-collection and local-album heroes share responsive
cover sizing, title hierarchy and transport controls. Native visual and touch acceptance is pending;
this work does not establish an exact copy of every Apple Music page.

Follow-up interface review adds a simulator-only XCUITest target and real queue gestures (drag,
swipe removal, picker selection, clear). The target is excluded from device running/archive builds.
Queue uses ordinary List mode so swipe actions remain available; long-press reordering comes from
onMove, with an SF Symbol grip matching the reference. Actual touch acceptance remains pending.
The Library Recently Added section groups imported albums into covers; per-song deletion remains
available from the shared song menu. Local playlist titles collapse into the navigation bar on
scroll; Edit lives in its More menu. Online albums share the same collection header as playlists.

Run 40303761472 at 7132980a compiled both Apple targets and directly downloaded artifacts confirm
all 23 local/native playback checks, including precise source duration, legacy doubled-duration
handling and the real forward-playback end event. All four download duration/legacy-data/playlist
restore checks also pass. The run failed only at the pre-existing Guest Google verification gate.
The screenshots exposed opaque backgrounds on non-song queue rows and automatic List disclosure
chevrons inside recent cover tiles. Those are corrected by clearing individual row backgrounds
and using state-driven navigation from cover buttons. The collection cover uses one measured
artwork view rather than multiple asynchronously loaded ViewThatFits candidates.

A manual changed_ui review scope is available only with publish_development=true. It runs the
real playback/end, download migration, local playlist/relaunch, queue and XCUITest checks, plus
populated screenshots, and records review-scope.json with full_provider_acceptance=false. The
normal unsigned acceptance artifact is not uploaded by this scope. Default push and full manual
runs keep the complete existing acceptance gate. This avoids rerunning unchanged network lyrics,
fonts and Guest checks for visual repairs; it does not establish successful Guest playback.

Focused run 40307540029 at 8e25098f compiled device and simulator plus the XCUITest runner. Native
playback/download/local-store/relaunch checks passed again. Downloads category/song/album/playlist
touch navigation passed. Queue drag did not reorder; a grip nested inside the row's playback Button
was not a reliable independent drag target. It is now a separate native drag source with a private
app-only occurrence payload, drop-enter reordering through PlaybackController, and VoiceOver Move
Up/Down actions. Swipe removal remains in ordinary list mode. The rename test reached its real
alert but failed because the accessibility tree exposed two Save button wrappers; the test now
selects the first matching button. No claim of passing these two touch flows is made yet.

Run 40326174606 at 04e5f7cb built the production device app with the separate private-UTI drag
grip. Simulator test compilation failed only in the XCTest gesture call: XCUIElement.press expects
an element destination, while the intended target was an XCUICoordinate. The source grip is now
converted to a coordinate before the coordinate-to-coordinate press/drag call. App playback code
was not changed by that repair. Run 40327404338 at 836e89bc is queued for the corrected focused
review. No build 12 has been delivered to LATEST-VERSION yet. Builds 10 and 11 remain unchanged.

Review artifacts are now split: Sonora-iPhone-simulator-review contains top-level count JSON and
screenshots; Sonora-iPhone-touch-review contains the detailed xcresult bundle. The runner also
exports touch-review-summary.json using xcresulttool when available, including on test failure.
The former combined artifact could reach 75 MB and delayed simple screenshot retrieval.

The standard macos-26 run remained queued without an assigned runner. GitHub's official hosted
runner table lists xcode-27 as a standard free public-repository arm64 image, and the official
runner image manifest lists Xcode 27.1 plus iOS 27 runtimes. The fork is confirmed PUBLIC. A
separate codex/iphone-ios27-review branch adds an explicit runner choice so an iOS 27 review can
run without canceling the waiting main-branch job. Simulator selection now requires support for
iPhone 13 instead of blindly choosing the numerically newest runtime. No paid runner is selected.
Sources: https://docs.github.com/en/actions/reference/runners/github-hosted-runners and
https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md .

Run 40329068868 at 39c766f1 compiled with Xcode 27 and selected an actual iPhone 13/iOS 27.0
simulator (24A434). Native playback/end, download storage and local/relaunch checks passed.
Two of three real touch tests passed: Downloads navigation and local playlist rename. Dragging
still failed its order assertion. The next diagnostic run advertises the custom non-secret queue
occurrence representation to the system drag service, records bounded simulator-only drag events
and exports failure screenshots when xcresulttool supports that filter. No stream URL or account
token is in the drag payload. This distinguishes a rejected drag representation from a model or
accessibility-order problem. The revised collection cover was visually confirmed sharp and loaded.
Download playlist manifests are also removed when the user clears account downloads, so old
playlist names do not reappear if the same song is downloaded under another account.

Run 40332339702 at faaa7ce0 passed the same two UI tests but still failed queue order. Its bounded
drag evidence contains only provider-start callbacks for both visible rows, with no validate,
enter or drop callbacks. The accessibility snapshot confirms that both occurrences remained in
their old positions. Changing provider visibility did not fix the SwiftUI List drop path.

The queue's scrollable content now uses UICollectionView's native list layout, always-visible
UICellAccessory.reorder and diffable-data-source reordering handlers, in normal mode with native
trailing swipe actions. SwiftUI still renders the shared artwork/font labels and existing player
header/transport. PlaybackController commits complete upcoming UUID order only when it matches
the current set, so past/current entries and stale drag snapshots are protected. History and
Add Songs remain non-reorderable rows; proposed destinations are constrained to upcoming songs.
Initial queue scroll positioning waits for a real viewport. The discarded custom drag/drop type
and provider have been removed. Two model checks cover accepted and rejected native reorders.
Primary SDK references: https://developer.apple.com/documentation/uikit/uicellaccessory-swift.struct/reorder(displayed:options:)
and https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource-9tqpa/reorderinghandlers-swift.property .
Native touch acceptance for this replacement is still pending.

Run 40336060273 at 8e37d227 compiled the UIKit queue for device and simulator. Its simulator run
never reached any review route: installation took about a minute and the initial simctl launch
timed out after 120 seconds, followed by slow shutdown. This does not establish a queue pass or
a queue runtime failure. The next build allows 240 seconds for cold initial launch, retaining
existing bounded warm-route and test timeouts. Native labels now receive the selected appTypeface
environment and reconfigure on font changes. Bottom scroll inset keeps Queue initially at the
top even when only a couple of songs follow it; history stays above and is revealed by scrolling.
