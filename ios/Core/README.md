# Mobile provider bridge

This isolated Cargo workspace reuses the desktop app's pinned `ytmusic-rs` client without
linking GPUI or the desktop audio engine. Isolation avoids building the desktop renderer for iOS.
Dependencies are declared at this workspace's root, and the YouTube revision matches Cargo.lock
in the main repository.

Operations include catalog search, Home/genres/details, lyrics, account sessions/library and
playlist mutations, plus native AAC stream resolution. Requests have a 30-second deadline;
resolution has 90 seconds for provider fallbacks. Stream addresses are ephemeral and must not be persisted.
The C API copies input synchronously, runs networking on Tokio and calls back on a worker thread.
The host owns each returned string until it calls the matching release function. Callers must
bound concurrency and keep callback contexts alive, including after the UI cancels its interest.
Errors are codes rather than raw HTTP output, to keep credentials and signed URLs out of the UI.

The app and workflow link this bridge. Keychain-backed sessions, native background transfer and
offline storage are integrated in Swift but still need runtime acceptance. Running the provider's normal stream inside Tokio
cannot promise iOS background downloading. AVPlayer receives a resolved AAC asset and its provider
user agent; native playback compatibility still needs integrated simulator/device verification.

Verified on Linux: Cargo check/build/Clippy, callback ownership, live catalog results and selected
stream resolutions. Device/simulator targets compile on the Apple runner, and simulator Home and
lyrics decode successfully. Guest audio is currently blocked there by Google's network verification;
see ../STATUS.md. Linux success does not establish working iPhone playback.

Local check: `RUSTFLAGS='' cargo check --manifest-path ios/Core/Cargo.toml` (overrides the
desktop workspace's mold linker flag when mold is not installed).
Native integration must build `aarch64-apple-ios` for iPhone and the matching simulator target,
link the static library and include `include/sonora_mobile.h` in a Swift bridging header.
