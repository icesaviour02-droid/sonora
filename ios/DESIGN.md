# Sonora iPhone design

Scope: the iPhone port only; desktop styling remains governed by its Rust theme.

Use the platform's native visual world, as explicitly requested: SwiftUI TabView, NavigationStack,
large titles, semantic system backgrounds, SF Pro text styles and SF Symbols. Follow the device's
light/dark preference. Keep the existing Sonora identity in the app icon.

The bottom tab bar is the system Liquid Glass capsule. A bottom accessory carries the mini-player;
the expanded player is a native sheet. Glass and glassProminent button styles are for actions,
not list rows or content backgrounds. No manual blur overlays or imitation glass.

Library, Search and Downloads are destinations. Settings is a toolbar sheet. Library starts with a
real empty state and an import action. Never manufacture music, artwork, completion or provider status.

All hit targets are at least 44 points. Use Dynamic Type, semantic foreground styles, native
VoiceOver labels and system sheet/back gestures. Built-in materials handle reduced transparency;
custom animation must respect reduced motion. No decorative looping animation.

Mode: Operate. First milestone: import audio, find it, play it, change queue position and recover
the library after relaunch. Streaming integration is a later milestone, clearly stated in Settings.
