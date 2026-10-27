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
| Mini-player text | 15 pt semibold / 15 pt regular; zero extra gap | FadingText, full label contrast |
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

## Build 18: 13:46 video and Songs comparison

Local-only refs: build18-apple-motion.mp4, build18-apple-metadata-swipe.png, build18-sonora-player.png, build18-apple-songs.png, build18-sonora-songs.png. Only these references were sampled; no new Sonora appearance screenshots were generated.

The 384 x 832 video shows approximately 250 px paused versus 340 px playing art, sharing its center. The target ratio is 0.735, the playing cover is 10 pt wider than each 32 pt text margin, and play/pause uses a critically damped 0.48-response spring with a lighter cover-shaped shadow. Artwork-mode transport reserves 100 pt; the artwork slot is offset -12 pt to preserve the measured center while leaving footer/volume placement stable. These are measured implementation targets, not a guarantee of pixel identity.

Expanded title/artist are 20/20 pt at normal Dynamic Type; mini-player title/artist are 15/15 pt. Selected fonts/accessibility scaling remain intentional. Hidden target and visible metadata use the same UILabel-derived heights, including descenders. Both metadata lines clip inside one stationary trailing gradient before favorite/menu controls; this also contains adjacent track text during swipes. No double per-label gradient is used in this visible layer.

Horizontal artwork/title gestures preview real adjacent queue UUIDs, follow translation directly, use projected release and resist missing neighbors. Selection preserves paused state. Native Library editing stays inline, with check circles/native reorder handles, recents moving out, optional categories moving in, and a Done toolbar. Category order and visibility persist. The root Library has no search; its individual collection pages retain search. Main Search lists only the remote service implemented in this target (YouTube Music). Songs Play/Shuffle sections suppress action-row and section separators.

Volume still uses normal MPVolumeView and public image/geometry APIs. Its native host aligns speaker symbols with the reported track center, with retina capsule end caps and no whole-view scaling/blur. Physical hardware volume cannot be accepted on the simulator. Apple reference: https://developer.apple.com/documentation/mediaplayer/mpvolumeview.

Build-18 native compilation and seven targeted touch cases are pending; check STATUS.md and current delivery validation for the final outcome.

## Added player-to-pill, queue-action and seeking references

The 13:59 video shows the cover traveling into the actual accessory cover rather than the whole player zooming into the pill. The 14:37 video shows favorite/menu visuals following the compact metadata position. Local files: build18-apple-player-pill.mp4, build18-apple-queue-actions.mp4, build18-apple-history-heading.png and build18-sonora-history-heading.png.

PlayerHeroState now measures the native mini-player/player cover in one UIWindow and moves a shared high-resolution cover with UIKit's real sheet transition coordinator, including interactive cancellation. It restores both real covers after the flight; native modal gestures remain. No private transition API is used. Favorites and the overflow menu keep real native controls while one non-interactive visual layer follows their measured mode-transition geometry. History row cells clip below the pinned heading; floating player overlays use the same upper cutoff, avoiding text/art above or behind History/Clear. Queue badge glyphs correspond to real shuffle/repeat/autoplay states; unsupported Apple-only mixing controls are not faked.

Progress input is a full-target native UIControl with tap/drag mapping and adjustable accessibility. PlaybackController performs exact seeks, guards stale completions and holds the requested display position until the native clock confirms. A new interaction case checks AVPlayer.currentTime after tapping ~80% and dragging to ~25% of a real local audio file.

The inline Library implementation now uses native List selection/check circles and persisted category binding because the initial custom-button-in-editing-list test did not preserve the selection. The test checks resulting category visibility and relaunch persistence. Downloads search assertions now address the current identified Songs list rather than any matching text in the underlying root page.

Native compilation of source 46c6ef26240f50e2810b8bab80dcb99aa02319d6 passed for both targets in run 40482593645. Its eight-case interaction report is pending. Build 17 remains the last delivered IPA until the replacement is accepted.

## Final build-18 acceptance and delivery

Source d15d7b9c3d6beccc68b6866c3c87b3a6239728ba; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40504942163. Both native targets compiled. All eight iPhone 13 / iOS 27.0 (24A434) interaction cases passed; zero failures and no runtime warnings reported. The final checks include scoped Downloads search/navigation, playlist rename, player/lyrics/menu/dismiss/reopen (one real Song Actions menu), native queue reorder/swipe/add/clear without app exit, history clipping/Clear/available transport, artwork-forward and metadata-back queue swipes, inline Library selection plus relaunch persistence/no root search, and tap/drag seeking checked against AVPlayer.currentTime of real local audio.

Delivered: ios/build/LATEST-VERSION/Sonora-0.3.0-build18-d15d7b9c.ipa; 8,603,227 bytes; SHA256 920dc4e7154ea721eba5be4e4cc4270df1d428ea5d03a5564cfd755c328ca0bd. Device ZIP/metadata/Mach-O arm64 iPhoneOS integrity verified; no test bundles packaged. Unsigned for iLoader. Previous IPA files remain intact and build-17 delivery notes are preserved under Previous-Versions. Small JSON is stored in CHECKS/ios27-build18-*.json; current BUILD-INFO.json and VALIDATION.md describe this exact candidate.

The duplicate menu and queue-editing exit from the previous run did not recur. The exact earlier crash stack was unavailable, so do not claim a confirmed crash root cause beyond the validated safer mask handling. No app screenshots were exported or visually reviewed and no iOS 26 tests ran. Native behavioral acceptance does not certify exact Apple Music pixel/motion identity or physical system-volume behavior. Guest/authenticated streaming, downloads from a live provider, signed-phone account persistence, background audio and AirPlay were not repeated in this UI run. Safari sign-in, additional remote providers and complete desktop parity remain unfinished. The implemented queue modes are shuffle, repeat and autoplay; unsupported Apple-only mixing controls are not faked.


## Build 19: 19:31 / 20:01 fullscreen, context menus and mini-player

Reference videos are local-only: build19-apple-fullscreen.mp4 contains lifted queue/history menus; build19-apple-queue-volume.mp4 shows fullscreen pull-down, reopening and idle/active volume. JPEG pairs compare Baby/Passionfruit full player and Payphone/Passionfruit minimized pill. The reference Apple player backdrop extends behind status bar, without the large-sheet inset.

The replacement presentation uses a full-window custom UIKit container, retained presenter and one interruptible property animator with a percent-driven downward dismissal. The cover flies between the actual source/destination anchors in that same animator; cancel restores the cover and panel. Native collection scrolls and explicit transport/seek/volume/actions rectangles keep their gestures. Reduced Motion fades. Only actual dismissal completion releases the retained hosting controller; first acceptance caught failed reopening when cleanup occurred inside the animator instead.

Queue title/artist and real favorite/menu actions stay in one root-space overlay. There is no end-of-motion replacement of static glyphs with controls. Mode geometry refinements retarget the spring; queue scrolling directly updates all overlay origins. Native collection context menus supply lifting, preview, backdrop and cancellation. Play Next/Last moves actual upcoming UUIDs and doesn't duplicate them. Imported songs use local playlists; remote songs show actual editable YouTube playlists, never an unresolvable local ID entry.

Default mini-player target: 14 pt semibold title /14 pt regular artist, 30 pt art inline and32 pt expanded, selected typeface/Dynamic Type retained. The inline explicit badge is removed so the two lines reach their normal trailing fade. In the supplied crops, pill widths are both approximately630 px; Apple play center is approximately89 px from the right edge, Sonora111 px. Inline trailing padding is therefore reduced from16 pt to8 pt, retaining the44 pt play target and16 pt leading inset. This moves its center8 pt right and lets both text lines reach the reference fade boundary. These are implementation measurements, not a physical pixel-match certificate.

Volume targets6 pt idle/18 pt active, with8 pt outward extension each side and0.22 s retargetable activation. A display link redraws tiny native track images and changes width/brightness together rather than scaling/blurring the view. The actual public UISlider track rectangle aligns speakers to the system control's baseline; MPVolumeView public geometry is the fallback. Hardware volume remains the native system control. Apple's original Music source wasn't found; https://developer.apple.com/documentation/mediaplayer/mpvolumeview and https://github.com/pratikg29/Custom-Slider-Control were inspected. The public recreation is not Apple's source, and no code was copied.

First run40526280563: both targets compiled,9/10 cases passed with no runtime warnings. Full-window bounds, canceled pull, committed artwork pull and queue/history menus passed. Reopening after interactive dismissal failed and is under correction. No new app appearance screenshots were exported or inspected; full exact visual/motion and hardware-volume acceptance remain for phone review. Build18 stays last accepted until final results are recorded in STATUS.md and delivery validation.


## Final build-19 acceptance and delivery

App source b10b94a365c255c91e09d5d8b4d849c647c01e1e; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40531111456. Both native targets compiled. All ten targeted iPhone 13 / iOS 27.0 (24A434) interaction cases passed, with zero failures and no runtime warnings.

The added fullscreen case confirmed the player covers the full window, survives a canceled pull, dismisses from artwork, reopens afterward, and dismisses again from empty space. Debug lifecycle flags confirm cancel retained the presented controller, committed cleanup occurred with no presented controller remaining, reopening presented a new controller, and the second pull cleaned up. This validates the UIKit-completion cleanup fix; the previous candidate's reopening failure did not recur. The added context-menu case moved an actual queue occurrence with Play Next, removed it, opened a history-row menu and removed that history entry. Existing eight touch regressions also passed, including native audio clock seeking, queue reorder/swipe/add/clear, history clipping, artwork/metadata horizontal swipes, Library persistence, Downloads/search/navigation, playlist rename and player/lyrics-source/menu return.

Delivered: ios/build/LATEST-VERSION/Sonora-0.3.0-build19-b10b94a3.ipa; 8,603,290 bytes; SHA256 2dd529d51489dcdd775d1db0dc63104a8680c7c50a73b456caf04bb7ec56119a. Unsigned for iLoader. ZIP integrity, device metadata, arm64 iPhoneOS Mach-O platform and absence of test bundles were verified. Build 18 and all previous IPA files remain untouched; build-18 delivery notes were saved under Previous-Versions. Current BUILD-INFO.json, README.txt, VALIDATION.md and CHECKS/ios27-build19-*.json describe the accepted candidate. Documentation-only commits after the app source do not alter this artifact.

No app appearance screenshots were exported/visually reviewed and no iOS 26 tests ran. Native behavior acceptance does not certify one-to-one Apple Music visual/motion identity or physical system volume. Only supplied reference media was sampled. No original Apple Music source was obtained. Live YouTube streaming/downloads, authenticated account persistence, background audio and AirPlay were not repeated in this UI run. System Safari sign-in, additional remote providers and complete desktop parity remain unfinished. Native provider playlist operations compile and are appropriately routed, but require a signed-in phone account for live acceptance.


## Build 20: marked Payphone full-player pair and collection/menu videos

The Apple reference is the screenshot with the hand-drawn A. Both images are740 x1600, representing390 x844 points. Apple's playing cover begins aroundx46/y151, versus Sonorax42/y153; the target becomes342 pt with24 pt side margins. The Apple grabber spans roughly114 px (60 pt) versus Sonora75 px (40 pt), and is7 pt higher. Favorite and overflow centers move outward10/6 pt respectively by reducing their internal gap4 pt and moving their shared target6 pt. Previous/next centers move inward12 pt, play/pause target glyph44 pt, transport group14 pt higher. Elapsed/remaining labels move10 pt upward, footer inner inset26 pt and5 pt visual drop. Existing title/artist font settings and accessibility scaling remain. These are implementation targets from the supplied pair, not certified physical-device measurements.

Source changes/limits and all evidence are recorded in STATUS.md, Build20. Only the user's videos were frame sampled. Fullscreen transition now uses native UIKit preferredTransition.zoom for the entire page from the live accessory. There is no detached artwork image. Native context highlight/dismiss targets point to the actual pressed cell; the owned history mask cannot interfere during the menu interaction. Collection sources now cover artwork only, and Recently Added, artist albums and offline collections gain missing native cover zoom links. Root category separators are explicit. Native toolbar IDs/placements remain consistent across hierarchy changes.


## Final build-20 UI acceptance and delivery

Source d03b6d964f008750c3888a6b284695a2e3fffbd0; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40553369272. Both native targets compiled; all eleven iPhone13/iOS27.0(24A434) targeted interaction cases passed, with zero runtime warnings. Queue and history actual-cell highlight/dismiss preview evidence was exported and verified. Full-window drag/cancel/artwork-dismiss/reopen/empty-space-dismiss passed, alongside native clock seeking, track swipes, history clipping, queue editing, Library persistence, Downloads/search, playlist rename/player menus and actual recent-collection open/back/toolbar actions.

Delivered UI candidate: ios/build/LATEST-VERSION/Sonora-0.3.0-build20-d03b6d96.ipa;8,624,777 bytes;SHA256032c27eeb5e2af597d0de9f8a566b145c39db582e0bfcdab08de9e71018a39ed. All package/device checks passed; unsigned for iLoader. Build19 and earlier files preserved, with build19 notes under Previous-Versions. No app appearance screenshots were exported/reviewed and no iOS26 tests ran. This uses the tested full-window UIKit custom presenter/percent driver with all real player elements inside one translating surface. The attempted system preferredTransition.zoom modal was removed after its regression; do not describe the delivered fullscreen player as that system modal zoom. Collection navigation remains native cover zoom. Physical exactness and volume need phone review; provider/account/background/AirPlay limits unchanged.

Reference files are local-only: build20-collections-comparison.mp4 (21:20), build20-sonora-context-menu.mp4 (21:53), build20-apple-player-dismiss.mp4 (21:46), build20-apple-player.png and build20-sonora-player.png. The later lyric-download request is not included in this UI20 IPA; it is being built as21.


Build22 refinement (pending native acceptance): offline capsule has an independent+16pt vertical offset relative to the unshifted time row, while elapsed/remaining retain-10pt. It remains horizontally centered in the gap before transport. Volume is now plain MPVolumeView with native internals and no custom expansion/external icons, as explicitly permitted by the user. A committed player dismissal begins artwork-to-pill handoff only after release and at/after60% of surface travel; actual image nodes and presentation-layer displacement avoid detached artwork during the finger drag. Original Apple video remains the reference; exact phone appearance is not certified.
