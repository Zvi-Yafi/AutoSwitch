# Verification — 1.1.2 (build 11)

Source review and targeted validation on 2026-10-25:

- The language engine matches the tested source with SHA-256
  `118e77f200f8faf08eb3141f6c17e91783678453f1c482c5153b21e1350a0299`.
  Fourteen isolated policy scenarios passed, including complete geresh translation,
  fallback, ignored words, target restrictions, confidence and ambiguity handling.
- Permission onboarding matches the tested source with SHA-256
  `c3d4d3f8197de0700bcca6f798e8352f8daee2b6c1514c3595aba8ce603c2c64`.
  Ten isolated control-flow scenarios passed, and the full Debug build succeeded.
- A locally signed Debug app was launched from Applications on the maintainer's
  Mac after resetting only its Input Monitoring and Accessibility approvals.
  The Input Monitoring list was observed empty before launch and contained
  AutoSwitch afterward, without the test operator adding it using the plus button.
  Both permissions were subsequently observed enabled. This was an existing user
  account after permission reset, not a never-used Mac.
- Only version/build metadata and release documentation changed after these
  tests. Production Swift sources and application resources match the tested copy.
- The isolated harnesses use in-memory services. They do not establish end-to-end
  text correction or macOS privacy-database behavior by themselves.
- The full XCTest suite was not rerun for 1.1.2. The updated dictionary-dependent
  geresh XCTest was not executed. Intel runtime, fresh-machine installation,
  downloaded-DMG installation and broad secure-field/focus regression coverage
  remain outside this validation scope. See TESTING.md.

Artifact signing, notarization and checksums must be verified for the final
build from the release commit; the GitHub release notes record those results.
Earlier release evidence below applies to 1.1.1 and is not a new test run.

## Previous release — 1.1.1 (build 10)

Verified on 2026-10-15 for direct distribution from GitHub.

- Updated Input Monitoring onboarding to register access in the background and
  handle granted, denied and pending states before opening macOS privacy settings.

- Debug: 40 tests passed, 2 skipped, no failures.
- Release: 35 tests passed, 2 skipped, no failures.
- Two tests require additional Latin keyboard layouts not installed on the test Mac.
- Five state-machine tests intentionally run only in Debug because they require debug hooks.
- Production logging privacy regressions passed.
- Universal arm64/x86_64 build succeeded; Developer ID signature verified with
  Hardened Runtime and a secure timestamp.
- Apple accepted both the app and DMG for notarization; both tickets were stapled
  and validated. Gatekeeper accepted both as `Notarized Developer ID`.
- Mounted the final DMG read-only and verified the included app's signature,
  notarization ticket and version (1.1.1, build 10). The DMG checksum passed.
- No previous private Git history, user settings, log files, credentials or private
  signing keys are included in this source publication.

This is a targeted review, not a guarantee of absence of every possible sensitive value.
The public GitHub account hosting the project is visible. The signed downloads
include the public Developer ID certificate, which identifies the certificate owner.
The private key and notarization credentials remain in the local Keychain.

The maintainer reported that the earlier beta installed and worked in local manual
tests. This release changes permission onboarding and build metadata; the language
correction engine is unchanged. First-launch permission prompts on a clean Mac,
full keyboard and secure-field coverage, Intel runtime testing and installation on
a separate Mac remain outstanding. See TESTING.md.
