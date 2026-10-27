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
