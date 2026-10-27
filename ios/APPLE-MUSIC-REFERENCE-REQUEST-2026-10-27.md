# Apple Music reference follow-up

## User brief

Use all WhatsApp images and the video in `ios/References`. Red accents identify Apple Music; other accents identify Sonora. Prefer public source research via Firecrawl, official Apple documentation and the supplied video. Do not claim that third-party replicas are Apple's private source. Use `/home/icesaviour/.codex/skills/apple-design/SKILL.md` from Emil Kowalski. Never use Impeccable.

Match queue opening: large art and metadata shrink/move into the top header. Queue history belongs ABOVE the current song header and mode controls, with resistant scrolling and threshold haptics. Keep native reorder, swipe removal, playback and Add Songs functional.

Match Songs alphabetical groups and right-side index, Artists alphabetical list/circular art/index, Playlists two-column listing/opening transition/cover-derived detail theme, Albums grid/list/sort menu and detail layout, and Downloads category rows/recent grid. Match typography, placement, icons and touch targets from the actual reference. Size mini-player artwork to the reference in expanded and collapsed placements; preserve title fade and artist line. All page titles, large or collapsed, must follow Settings' selected font.

Implement corresponding real Sonora actions in menus; don't add cosmetic dead actions for unsupported Apple-only functions. Maintain downloaded/streamed playback, queue identity, existing local playlists and account persistence. Preserve build 13 as rollback. The target is iPhone 13 and the user's reported iOS 27. Don't run iOS 26 tests or generate repeated screenshots. Targeted compilation and interaction checks are allowed and needed.

The earlier 04:30 IST scheduling request was not completed, and the user said continue after that time passed. Continue work directly; do not create a recurring schedule.

## Starting point and evidence

Build 13 source: e68685060fa4363a13283511e8bbd448366e554c. IPA: ios/build/LATEST-VERSION/Sonora-0.3.0-build13-e6868506.ipa. SHA256: b339918ad2fe28aaa83c468c4e3d04a01e037e3d23b9447e3f3cd248cb8355d7.

Prior GitHub run 40387301121 completed with failure and was not canceled. Its small JSON was downloaded into ios/build/build13-final-review: all four touch tests passed; Home/Search succeeded; Keychain returned -34018 and Guest audio was blocked by network_verification_required. Do not repeat the prior simulator-signing experiments. Earlier run 40374499230 passed 92 native assertions and 3/4 UI cases, with picker/keychain/provider acceptance incomplete. Native Keychain and physical phone acceptance remain open. Linux live provider probes resolved, downloaded and decoded real AAC with correct duration and zero trailing silence, but do not establish physical iPhone playback.

See ios/STATUS.md and ios/PARITY.md for implementation/feature limits. Current build-14 source progress is recorded in STATUS. All new native source is discovered by ios/scripts/prepare.py, including project/strings regeneration. GH CLI: /home/icesaviour/.cache/sonora-tools/gh/bin/gh. Fork: icesaviour02-droid/sonora. Use the xcode-27 workflow, functional scope only when needed. No credentials or reference personal media belong in CI artifacts or public commits.

## Sources checked this turn

- https://developer.apple.com/documentation/uikit/uinavigationbarappearance — native title and large title text attributes.
- https://developer.apple.com/documentation/uikit/uinavigationbar — preserve native glass material; customize font attributes only.
- https://developer.apple.com/documentation/swiftui/view/sectionindexlabel(_:)
- https://developer.apple.com/documentation/swiftui/view/listsectionindexvisibility(_:) — native List alphabet index, available for the iOS 27 target.

Public-source search returned official APIs and third-party MusicKit examples; no original Apple Music queue implementation was obtained. Supplied media governs the requested motion.

## Resolved build-service blocker and current candidate

The user clicked the fork's green re-enable workflows button. Actions is restored. Build 14 run 40435163817 compiled device and simulator successfully, then was canceled to test the new lyrics-menu source instead. Its verified IPA is preserved in ios/build/LATEST-VERSION/Previous-Versions.

Current source: d621802b1342e7605347c7dcb47b17861fcb591e (build 15). Run: https://github.com/icesaviour02-droid/sonora/actions/runs/40435748036. Device and iOS 27 simulator compiled. Verified IPA: ios/build/LATEST-VERSION/Sonora-0.3.0-build15-d621802b.ipa. SHA256: 659f6654e701d751c793cfa5ea7f9ea821f5d83f4dbaac1824165237bd62d4d9. Functional tests are pending; inspect that run's small JSON and current VALIDATION.md before making claims.

The latest user request moves lyrics-source options to a separate fixed footer immediately above progress. Source caption is single-line; button has a stable 44 pt target. The footer is outside the lyric timeline/scroll view and ignores inherited SwiftUI animation. Native menu source selection/settings/import/copy/refresh remain. The existing player interaction case now opens Lyrics Sources from this menu, dismisses its sheet, and checks that the footer button remains hittable. Do not claim that this covers timed scrolling glitches or a physical device until observed.

## Current UI candidate: build 16

The user supplied new 08.02 Library/queue comparisons after build 15. Source 60a9536cfad861e4c122337cc91959df1d30c98d implements the updated layout targets in ios/References/UI-REFERENCE-METRICS.md, one persistent high-resolution player cover guided by active geometry targets, shared row/grid metrics, a native inline-large Library title and toolbar grouping, persisted category visibility, real collection recents, corrected mini-player hierarchy, history spacing and thin native seek/volume controls. No reference media is packaged or pushed.

Run 40442189850 passed device/simulator compilation and all four iPhone 13 / iOS 27 touch cases. Current IPA is ios/build/LATEST-VERSION/Sonora-0.3.0-build16-60a9536c.ipa; checksum 58c72080c23d5ccb8bcc0b77204b525275e4fb563fd9659ae5ad21f344bc5f3c. Read VALIDATION.md for the limits. This is a UI candidate, not complete Apple Music/desktop/provider parity. Physical motion/layout and new seek/volume behavior need phone review. Earlier IPAs remain intact.

## Latest delivered candidate: build 17

Source cf433d7f809e5c6350456649239daf3a3677a2c2; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40465544047. IPA: ios/build/LATEST-VERSION/Sonora-0.3.0-build17-cf433d7f.ipa. SHA256: 1cb7ba239dd0f7bee462dd56515a0945308e29000d93d595e5521e8579f2f303. Build 16 and earlier IPAs remain intact.

The seven 09:09–09:28 images govern the new volume/mini-player/search/history targets. Cover and metadata share a persistent viewport clip ending at progress in every player mode. Metadata is one visible interpolating layer. Queue header controls are native scrolling content; a hidden geometry twin supplies the single visible cover/title positions. History has a pinned native heading and 24 pt footer gap. MPVolumeView has 6 pt idle / 18 pt touched track, widening and speaker displacement. Mini-player baseline is 17/15 pt with 32 pt expanded / 30 pt inline art. Collection search is a native drawer with real metadata filtering; search preserves navigation toolbar content so Back remains accessible.

Both native targets compiled, and all five targeted iPhone 13 / iOS 27.0 touch cases passed with no runtime warnings. The earlier failed attempts and resulting fixes are recorded in STATUS.md; they were not promoted. No appearance screenshots were generated/inspected and no iOS 26 tests ran. Physical volume, visual/motion identity and full provider/account/background acceptance remain outside these checks. See current VALIDATION.md, PARITY.md and build-17 small JSON before claiming feature parity.

## Final build-18 acceptance and delivery

Source d15d7b9c3d6beccc68b6866c3c87b3a6239728ba; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40504942163. Both native targets compiled. All eight iPhone 13 / iOS 27.0 (24A434) interaction cases passed; zero failures and no runtime warnings reported. The final checks include scoped Downloads search/navigation, playlist rename, player/lyrics/menu/dismiss/reopen (one real Song Actions menu), native queue reorder/swipe/add/clear without app exit, history clipping/Clear/available transport, artwork-forward and metadata-back queue swipes, inline Library selection plus relaunch persistence/no root search, and tap/drag seeking checked against AVPlayer.currentTime of real local audio.

Delivered: ios/build/LATEST-VERSION/Sonora-0.3.0-build18-d15d7b9c.ipa; 8,603,227 bytes; SHA256 920dc4e7154ea721eba5be4e4cc4270df1d428ea5d03a5564cfd755c328ca0bd. Device ZIP/metadata/Mach-O arm64 iPhoneOS integrity verified; no test bundles packaged. Unsigned for iLoader. Previous IPA files remain intact and build-17 delivery notes are preserved under Previous-Versions. Small JSON is stored in CHECKS/ios27-build18-*.json; current BUILD-INFO.json and VALIDATION.md describe this exact candidate.

The duplicate menu and queue-editing exit from the previous run did not recur. The exact earlier crash stack was unavailable, so do not claim a confirmed crash root cause beyond the validated safer mask handling. No app screenshots were exported or visually reviewed and no iOS 26 tests ran. Native behavioral acceptance does not certify exact Apple Music pixel/motion identity or physical system-volume behavior. Guest/authenticated streaming, downloads from a live provider, signed-phone account persistence, background audio and AirPlay were not repeated in this UI run. Safari sign-in, additional remote providers and complete desktop parity remain unfinished. The implemented queue modes are shuffle, repeat and autoplay; unsupported Apple-only mixing controls are not faked.


## Final build-19 acceptance and delivery

App source b10b94a365c255c91e09d5d8b4d849c647c01e1e; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40531111456. Both native targets compiled. All ten targeted iPhone 13 / iOS 27.0 (24A434) interaction cases passed, with zero failures and no runtime warnings.

The added fullscreen case confirmed the player covers the full window, survives a canceled pull, dismisses from artwork, reopens afterward, and dismisses again from empty space. Debug lifecycle flags confirm cancel retained the presented controller, committed cleanup occurred with no presented controller remaining, reopening presented a new controller, and the second pull cleaned up. This validates the UIKit-completion cleanup fix; the previous candidate's reopening failure did not recur. The added context-menu case moved an actual queue occurrence with Play Next, removed it, opened a history-row menu and removed that history entry. Existing eight touch regressions also passed, including native audio clock seeking, queue reorder/swipe/add/clear, history clipping, artwork/metadata horizontal swipes, Library persistence, Downloads/search/navigation, playlist rename and player/lyrics-source/menu return.

Delivered: ios/build/LATEST-VERSION/Sonora-0.3.0-build19-b10b94a3.ipa; 8,603,290 bytes; SHA256 2dd529d51489dcdd775d1db0dc63104a8680c7c50a73b456caf04bb7ec56119a. Unsigned for iLoader. ZIP integrity, device metadata, arm64 iPhoneOS Mach-O platform and absence of test bundles were verified. Build 18 and all previous IPA files remain untouched; build-18 delivery notes were saved under Previous-Versions. Current BUILD-INFO.json, README.txt, VALIDATION.md and CHECKS/ios27-build19-*.json describe the accepted candidate. Documentation-only commits after the app source do not alter this artifact.

No app appearance screenshots were exported/visually reviewed and no iOS 26 tests ran. Native behavior acceptance does not certify one-to-one Apple Music visual/motion identity or physical system volume. Only supplied reference media was sampled. No original Apple Music source was obtained. Live YouTube streaming/downloads, authenticated account persistence, background audio and AirPlay were not repeated in this UI run. System Safari sign-in, additional remote providers and complete desktop parity remain unfinished. Native provider playlist operations compile and are appropriately routed, but require a signed-in phone account for live acceptance.


## Final build-20 UI acceptance and delivery

Source d03b6d964f008750c3888a6b284695a2e3fffbd0; successful run https://github.com/icesaviour02-droid/sonora/actions/runs/40553369272. Both native targets compiled; all eleven iPhone13/iOS27.0(24A434) targeted interaction cases passed, with zero runtime warnings. Queue and history actual-cell highlight/dismiss preview evidence was exported and verified. Full-window drag/cancel/artwork-dismiss/reopen/empty-space-dismiss passed, alongside native clock seeking, track swipes, history clipping, queue editing, Library persistence, Downloads/search, playlist rename/player menus and actual recent-collection open/back/toolbar actions.

Delivered UI candidate: ios/build/LATEST-VERSION/Sonora-0.3.0-build20-d03b6d96.ipa;8,624,777 bytes;SHA256032c27eeb5e2af597d0de9f8a566b145c39db582e0bfcdab08de9e71018a39ed. All package/device checks passed; unsigned for iLoader. Build19 and earlier files preserved, with build19 notes under Previous-Versions. No app appearance screenshots were exported/reviewed and no iOS26 tests ran. This uses the tested full-window UIKit custom presenter/percent driver with all real player elements inside one translating surface. The attempted system preferredTransition.zoom modal was removed after its regression; do not describe the delivered fullscreen player as that system modal zoom. Collection navigation remains native cover zoom. Physical exactness and volume need phone review; provider/account/background/AirPlay limits unchanged.

Reference files are local-only: build20-collections-comparison.mp4 (21:20), build20-sonora-context-menu.mp4 (21:53), build20-apple-player-dismiss.mp4 (21:46), build20-apple-player.png and build20-sonora-player.png. The later lyric-download request is not included in this UI20 IPA; it is being built as21.
