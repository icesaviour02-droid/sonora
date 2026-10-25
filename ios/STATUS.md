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

These are source checks, not a Swift type-check, iOS build, simulator run or device test.

## Required next

1. A user-owned GitHub repository containing these changes, with Actions enabled.
2. Run the iPhone IPA workflow; fix any Apple SDK/compiler errors.
3. Review the simulator artifacts and sideload the test IPA on the iPhone 13.
4. Validate local playback, imports, queue behavior, background audio and accessibility.
5. Implement and validate the YouTube Music provider milestones in README.md.

No IPA has been generated or tested. No streaming provider or background download support has
been completed in the iPhone app. The first source milestone must not be represented as the
final feature-complete app.
