# Mobile provider bridge

This isolated Cargo workspace reuses the desktop app's pinned `ytmusic-rs` client without
linking GPUI or the desktop audio engine. Isolation avoids building the desktop renderer for iOS.
Dependencies are declared at this workspace's root, and the YouTube revision matches Cargo.lock
in the main repository.

Current operations: anonymous song search and native AAC stream resolution, with a 30-second
deadline and compact JSON responses. Stream addresses are ephemeral and must not be persisted.
The C API copies input synchronously, runs networking on Tokio and calls back on a worker thread.
The host owns each returned string until it calls the matching release function. Callers must
bound concurrency and keep callback contexts alive, including after the UI cancels its interest.
Errors are codes rather than raw HTTP output, to keep credentials and signed URLs out of the UI.

The app and workflow now link this bridge. Authentication, background transfer and offline storage
remain separate integration work. In particular, running the provider's normal stream inside Tokio
cannot promise iOS background downloading. AVPlayer receives a resolved AAC asset and its provider
user agent; native playback compatibility still needs integrated simulator/device verification.

Verified on Linux: Cargo check, build, Clippy with warnings denied, a manual callback/ownership
check and a live search returning 20 songs. This does not establish compatibility with iOS.

Local check: `RUSTFLAGS='' cargo check --manifest-path ios/Core/Cargo.toml` (overrides the
desktop workspace's mold linker flag when mold is not installed).
Native integration must build `aarch64-apple-ios` for iPhone and the matching simulator target,
link the static library and include `include/sonora_mobile.h` in a Swift bridging header.
