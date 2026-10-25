# Apple Music reference pack

Official reference images were retrieved on 26 October 2026. They are study material only and
are excluded from the app bundle and from Git by the local image ignore rules. Every image's
exact source URL and Apple source page is recorded in sources.json. They are not Sonora assets.

## Primary references

- S3101_musicNowPlaying_iPhone.png: Apple User Guide's sharp Now Playing screen. This governs
  artwork size, track header, progress, transport, volume and bottom lyrics/AirPlay/queue controls.
- S3109_musicMiniPlayer_iPhone.png: Apple User Guide's Library, pinned items, categories,
  floating mini-player and bottom glass tab bar.
- app-store-1.png: official Home screen, large recommendation cards, horizontal shelves, mini-player.
- app-store-2.png: official playlist creation presentation.
- app-store-3.png: official full-height lyrics layout, compact track header, timed lyric hierarchy.
- app-store-4.png: official current App Store screenshot; inspect before using its specific screen.
- app-store-5.png: official collection detail page and shelf composition.
- app-store-6.png: official radio collection and cards.

App Store images are 1287×2796-pixel renditions obtained from Apple's image CDN, not generated
mockups. Support-guide images have their original native dimensions. Some reference imagery
contains album covers, music branding or service-specific features that must not become fake
content or unsupported features in Sonora. No exact Apple Music app source code was found;
Apple's published UI kits are design resources, not its application implementation.

## Vector resources

Apple's official iOS/iPadOS UI Kit is linked from https://developer.apple.com/design/resources/.
Current official Figma link: https://www.figma.com/community/file/1651309003795292092/ios-and-ipados-27
Official Sketch link: https://www.sketch.com/s/04c24d8b-38fb-4afb-8836-36617e022f02
These editable resources are links, not files downloaded or inspected in this task. Use system
SF Symbols, SwiftUI TabView and native controls so icons/materials render as native vectors.

## Behavior sources

https://support.apple.com/guide/iphone/use-the-music-player-controls-iph676daac9b/26/ios/26
https://support.apple.com/guide/iphone/iphb9bf483aa/26/ios/26
https://support.apple.com/guide/iphone/queue-up-your-music-ipha4521ef7d/ios
https://www.apple.com/apple-music/

## Skill

Use emilkowalski/skills/skills/apple-design at revision 2d228630ba1446365f614a108cb8252f1feda202.
Installed at /home/icesaviour/.codex/skills/apple-design/SKILL.md. The user explicitly rejected
Impeccable for this implementation. Translate the Apple Design skill's web examples into native
iOS APIs: continuous gestures, interruptible springs, native materials and accessibility fallbacks.

## Sonora adaptations

Keep real YouTube Music data and local-file playback. Downloads uses Apple's Library/Downloaded
row and native progress-list vocabulary; an exact standalone Apple Music Downloads-tab screenshot
has not been found. Do not fabricate an exact reference or claim every screen has been verified.
