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
| Mini-player | 32 pt art expanded / 28 inline; 4 pt corners | Layout mini tokens |
| Mini-player text | callout 16 pt semibold / subheadline 15 pt regular; zero extra gap | FadingText, full label contrast |
| Queue current artwork | 72 pt | queueHeaderArtwork |
| History-to-current separation | explicit 24 pt spacer | historySectionGap |
| Player slider | 3 pt idle track, no large idle thumb, 44 pt touch surface | MusicSeekSlider / MPVolumeView image APIs |

Motion: one persistent high-resolution cover is rendered above layout placeholders. The full player and each compact header contribute bounds only while active. A non-bouncy 0.4-response spring animates frame/position; queue scrolling moves the header and cover together without an animated lag. Reopening the queue resets its initial offset. Do not replace this with two separately loading AsyncImage views cross-fading between modes.

Primary Library defaults: Playlists, Artists, Albums, Songs, Downloaded. Optional History, Pinned and Local Favorites are enabled through Edit Library, retaining their existing data and functionality. The toolbar groups creation/import and category editing; profile/settings remains separate. Recently Added uses actual local/provider covers, never reference artwork.

These are implementation targets, not a certification that every rendered page is pixel-identical. Verify real iPhone motion/layout through the user's feedback. Do not generate repeated appearance screenshots or test iOS 26. Preserve current working IPA when making further source changes.
