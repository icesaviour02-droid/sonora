# Apple Music layout targets — 27 October comparison

Study images are local references, never Sonora bundle assets. User images with red accents are Apple Music; pink-accent images are Sonora. No private Apple Music application source was obtained. Official SwiftUI/UIKit APIs and the user's supplied video govern the implementation.

The 08.02.49 Apple Music Library screenshot is 740 px wide and represents a 390 pt iPhone viewport (approximately 1.897 image pixels per logical point). The default SF typeface and normal Dynamic Type are the reference baseline; a user-selected custom font or accessibility size changes glyph metrics intentionally.

| Element | Target at baseline | Shared implementation |
| --- | --- | --- |
| Library title | 34 pt, bold, leading, on toolbar line | native inlineLarge + selected typeface |
| Library primary rows | 52 pt; zero added vertical row insets | LibraryCategoryLabelStyle / libraryCategoryRow |
| Primary category text | body, 17 pt | appFont(.body) |
| Category icon | 24 pt column, 16 pt text gap | Layout.categoryIcon / spacing |
| Page margins | 20 pt | Layout.pageMargin |
| Song / artist rows | 56 pt minimum, 48 pt artwork | musicListRow / Layout.rowArtwork |
| Grid | 2 columns; 12 pt horizontal gutter; 16 pt vertical gap | gridSpacing / spacing |
| Grid cover on 390 pt phone | (390 - 40 - 12) / 2 = 169 pt | flexible columns, no fixed 152 pt card width |
| Grid artwork corners | 8 pt | Layout.cardRadius |
| Song artwork corners | 4 pt | Layout.rowArtworkRadius |
| Mini-player | 32 pt art expanded / 30 inline; 4 pt corners | Layout mini tokens |
| Mini-player text | headline 17 pt semibold / subheadline 15 pt regular; zero extra gap | FadingText, full label contrast |
| Queue current artwork | 72 pt | queueHeaderArtwork |
| History-to-current separation | native 24 pt footer gap | historySectionGap |
| Player slider | 6 pt idle track, no large idle thumb, 44 pt touch surface | MusicSeekSlider / MPVolumeView image APIs |

Motion: one persistent high-resolution cover is rendered above layout placeholders. The full player and each compact header contribute bounds only while active. A non-bouncy 0.4-response spring animates frame/position; queue scrolling moves the header and cover together without an animated lag. Reopening the queue resets its initial offset. Do not replace this with two separately loading AsyncImage views cross-fading between modes.

Primary Library defaults: Playlists, Artists, Albums, Songs, Downloaded. Optional History, Pinned and Local Favorites are enabled through Edit Library, retaining their existing data and functionality. The toolbar groups creation/import and category editing; profile/settings remains separate. Recently Added uses actual local/provider covers, never reference artwork.

These are implementation targets, not a certification that every rendered page is pixel-identical. Verify real iPhone motion/layout through the user's feedback. Do not generate repeated appearance screenshots or test iOS 26. Preserve current working IPA when making further source changes.

## Build 17 follow-up

The new 09:09–09:28 references are saved locally as build17-apple-*.png and the dark comparison as build17-sonora-history-leak.png. Their media is not pushed or bundled.

Volume: 6 pt idle / 18 pt touched track, approximately 1.05 horizontal scale during touch, with speaker icons moving outward. MPVolumeView still controls hardware volume.

History: a real native pinned section header, a 24 pt footer gap, and a shared player-content mask ending at the progress track. The queue viewport extends into the empty upper half of the progress touch region; the native list reserves bottom inset for last-row actions. Moving cover and metadata never render over lower playback controls, including during mode changes. Metadata is one visible interpolating layer, not matched/cross-faded duplicate text.

Search: native navigationBarDrawer/automatic placement is shared across music collection pages, with real cached-metadata filtering. Queue/history and lyrics scrolling intentionally keep their player gestures instead of introducing search fields. Search does not mutate stored playlists; filtered local-playlist deletion uses displayed IDs and filtering disables reorder.

A history gesture test caught native sheet dismissal at the list's top. Non-artwork modes now keep overscroll inside the player, with handle tap/downward-release dismissal retained. The first search test used an unsupported snapshot predicate; it was corrected to inspect real XCUIElement hittability. These failures must not be reported as a passed first run.

The final queue header is native list content for gesture arbitration; only its geometry template is a hidden parent overlay. Header state changes update its hosting cell, while ordinary scroll offsets do not rebuild it. Collection search preserves native toolbar controls with searchPresentationToolbarBehavior(.avoidHidingContent), documented at https://developer.apple.com/documentation/swiftui/view/searchpresentationtoolbarbehavior(_:).

Final validation: run 40465544047 at cf433d7f809e5c6350456649239daf3a3677a2c2 passed both native builds and five targeted iPhone 13 / iOS 27.0 touch cases. The new history case checks that current-header input does not block scrolling, transport remains accessible, the scrolled header is no longer hittable past its viewport, and Clear restores it. The search case verifies real filtering/restoration and navigation into saved albums/playlists afterward. No appearance screenshots were generated or inspected; actual physical volume, animation fidelity and reference-perfect typography remain for phone review.
