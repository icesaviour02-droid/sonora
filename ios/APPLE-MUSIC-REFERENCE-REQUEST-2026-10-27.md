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
