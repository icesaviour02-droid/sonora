# Sonora iPhone design

Scope: the iPhone port only; desktop styling remains governed by its Rust theme.

## Design Reference & Visual World

The **Apple Music iPhone app** (iOS 26/27 Liquid Glass era) is the primary reference for every layout, appearance, navigation pattern, player transition and touch interaction. Retain Sonora's identity and app icon while accommodating all original Sonora desktop features in idiomatic Apple Music places.

## Navigation & Bottom Chrome

- **Liquid Glass Tab Bar**: System `TabView` capsule with `.tabBarMinimizeBehavior(.onScrollDown)` so the floating pill bar collapses smoothly when scrolling down and pops back up when scrolling up or interacting.
- **Top-Level Destinations**:
  - **Home** (`house.fill`): Personal and guest feed (`Listen Again`, `Quick Picks`, `From Your Library`, `Pinned` items, `Recently Played / History`, and `Genres & Moods` shelves).
  - **Library** (`music.note.house` / `square.stack.fill`): Apple Music-style category list at top (`Playlists`, `Artists`, `Albums`, `Songs`, `Downloaded`, `Imported`) with `Recently Added` below, plus toolbar actions for importing local audio and opening Settings.
  - **Downloads** (`arrow.down.circle`): Active and completed offline transfers with progress, retry and swipe-to-remove.
  - **Search** (`magnifyingglass`, `role: .search`): Floating search pill on the right of the tab bar that expands into the bottom search bar when active, supporting `YouTube Music` and `Library` scopes across Songs, Albums, Artists and Playlists, plus Genre browsing when the query is empty.
- **Mini-Player Accessory**: Hosted in `tabViewBottomAccessory` directly above the floating tab bar. Displays rounded track artwork thumbnail, track title, artist subtitle, play/pause button and next-track (`forward.fill`) button. Tapping or swiping up expands into the full-screen Now Playing view.

## Full-Screen Now Playing, Lyrics & Queue

- **Presentation**: Full-height sheet with top grabber capsule, interactive swipe-to-dismiss, and atmospheric background derived from the current track's artwork over dark material.
- **Three In-Player Modes** (toggled from the bottom bar, matching Apple Music):
  1. **Artwork Mode (Default)**:
     - Large square album artwork with rounded corners and deep shadow that scales dynamically (`1.0` when playing, `0.82` when paused) with a spring animation (respecting Reduce Motion).
     - Track title and artist header on the left; favorite (`star` / `heart`) toggle and overflow action menu (`ellipsis.circle.fill` for Play Next, Add to Queue, Start Radio, Add to Playlist, Download, Go to Album/Artist, Sleep Timer, Share) on the right.
  2. **Lyrics Mode** (`quote.bubble` active):
     - Compact top track header (small artwork thumbnail + title + artist + menu).
     - Full-height scrolling lyrics canvas: synced lines highlight at the active playhead and seek when tapped; inactive lines dim (and optionally blur per settings); supports romanization and plain-lyrics fallback with source attribution.
  3. **Queue / Up Next Mode** (`list.bullet` active):
     - Compact top track header.
     - Pill toggles for Shuffle (`shuffle`), Repeat (`repeat` / `repeat.1`), and Autoplay Radio (`infinity`).
     - Reorderable and swipe-deletable Up Next queue with History access.
- **Scrubber & Quality Badge**: Interactive progress bar with elapsed time on left, remaining time (`-0:00`) on right, and centered audio format/quality badge (`AAC`, `256 kbps`, `Downloaded`).
- **Transport Controls**: Large centered `backward.fill`, `play.fill`/`pause.fill`, and `forward.fill` buttons.
- **System Volume & Routing**: Native `MPVolumeView` slider flanked by `speaker.fill` and `speaker.wave.3.fill`, plus bottom row with Lyrics toggle, native `AVRoutePickerView` (AirPlay / Bluetooth), and Queue toggle.

## Sonora Feature Accommodation in Settings

Settings opens from the top toolbar and organizes all desktop Sonora capabilities into native grouped sections:
- **Music Services & Accounts**: YouTube Music sign-in, existing Cookie session import, account/brand-channel selection, cookie rotation status, and local Files import.
- **Playback & Audio Quality**: Streaming/download quality (High / Normal / Low), Gapless & Automix Radio continuation, Loudness Normalization, Sleep Timer, and Equalizer (presets and custom preamp/bass/treble).
- **Lyrics**: Synced/Karaoke highlighting, inactive-line blur, Romanization for non-Latin scripts, local-file lyrics lookup, and source priority (YouTube Music, LRCLIB).
- **Appearance**: Theme override (System / Light / Dark) and Now Playing motion options.
- **Downloads & Storage**: Cellular downloads toggle, offline storage usage, and cache/download clearing.
- **Scrobbling & About**: Last.fm / ListenBrainz / Libre.fm / Maloja configuration, version, and GPL-3.0-or-later license.

## Craft & Accessibility Rules

- All hit targets are at least 44×44 pt. Do not apply oversized `.glass` button wrappers inside dense list rows; use clean plain/borderless trailing menus on rows like Apple Music.
- Use Dynamic Type, semantic foreground styles, native VoiceOver labels and system back/sheet gestures.
- Never manufacture fake tracks, artwork, completion or playback status.
- Mode: Operate.

## Verified reference and implementation contract (26 October 2026)

Primary visual evidence now lives in References/AppleMusic with per-image sources, rather than an
approximate remembered Apple Music layout. Use the official sharp artwork composition, native glass
chrome, compact lyric header, reserved transport/volume region and touch targets of at least 44 pt.
Use Emil Kowalski's apple-design guidance; Impeccable is no longer the chosen skill for this project.

The player background is decorative and must never determine layout size. Bound it to the viewport,
keep foreground artwork unblurred, and fit its side to available width and height. Large Dynamic Type
gets a scrolling layout. Honor Reduce Motion and Reduce Transparency. Never enlarge low-resolution
row artwork for the hero when the provider can serve a larger rendition. Downloads adapts the native
Library/Downloaded vocabulary; no exact Apple standalone-download-tab reference has been found.
