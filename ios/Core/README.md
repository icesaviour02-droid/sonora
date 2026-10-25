# Mobile provider bridge

This isolated Cargo workspace reuses the desktop app's pinned `ytmusic-rs` client without
linking GPUI or the desktop audio engine. Isolation avoids building the desktop renderer for iOS.
Dependencies are declared at this workspace's root, and the YouTube revision matches Cargo.lock
in the main repository.

Current operation: anonymous song search, with a 30-second deadline and a compact JSON response.
The C API copies input synchronously, runs networking on Tokio and calls back on a worker thread.
The host owns each returned string until it calls the matching release function. Callers must
bound concurrency and keep callback contexts alive, including after the UI cancels its interest.
Errors are codes rather than raw HTTP output, to keep credentials and signed URLs out of the UI.

This bridge is not yet linked into the SwiftUI app or the IPA workflow. Authentication,
playback, background transfer and offline storage remain separate integration work. In particular,
running the provider's normal stream inside Tokio cannot promise iOS background downloading.

Verified on Linux: Cargo check, build, Clippy with warnings denied, a manual callback/ownership
check and a live search returning 20 songs. This does not establish compatibility with iOS.

Local check: `RUSTFLAGS='' cargo check --manifest-path ios/Core/Cargo.toml` (overrides the
desktop workspace's mold linker flag when mold is not installed).
Native integration must build `aarch64-apple-ios` for iPhone and the matching simulator target,
link the static library and include `include/sonora_mobile.h` in a Swift bridging header.
