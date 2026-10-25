# iPhone port status

Initial source milestone, 25 October 2026. Target: iPhone 13, iOS 26+.

## Checked on Linux

- All six Swift sources parse without syntax errors using the tree-sitter Swift grammar.
- The generated Xcode project's references and source paths resolve.
- Info.plist, shared scheme XML and asset JSON parse successfully.
- Canonical Fluent keys cover all explicit iOS localization keys.
- Regeneration produces identical output.
- Build workflow YAML parses and requests read-only repository access.
- Native design detector reports no findings.
- `git diff --check` passes.

The cloud packaging step also rejects simulator bundles, requires arm64 device code and verifies
the IPA archive structure before upload. That step has not run here because it requires an
actual Xcode device build. Library/queue restoration now shares one entry point so observer
ordering cannot overwrite a saved queue before it is restored.

## Cloud build verified

- Fork created at https://github.com/icesaviour02-droid/sonora.
- Initial source commit: `93af5a9b`.
- Run https://github.com/icesaviour02-droid/sonora/actions/runs/40191763029 successfully built
  both device and simulator targets with Xcode.
- Device IPA packaged/uploaded; downloaded to `build/first-ipa/Sonora-unsigned.ipa`.
- Downloaded bundle verified as arm64 iPhoneOS, minimum iOS 26.0, with intact ZIP contents.
- Simulator boot/screenshots were still running when this record was written.

## YouTube bridge verified separately

`Core/` builds independently of GPUI using the desktop-pinned YouTube client. Cargo check,
build and Clippy with warnings denied pass on Linux. A manual native-boundary invocation verified
the callback/string-release contract and an invalid-query response; a live Beethoven search
returned 20 results. This bridge has not been linked or cross-compiled into the IPA yet.

## Required next

1. Review simulator artifacts and sideload the test IPA on the iPhone 13.
2. Validate local playback, imports, queue behavior, background audio and accessibility.
3. Cross-compile/link the YouTube bridge and implement the provider milestones in README.md.

The first IPA has been generated but has not been tested on a physical device. No streaming
provider or background download support has been completed in the iPhone app. This development
milestone must not be represented as the final feature-complete app.
