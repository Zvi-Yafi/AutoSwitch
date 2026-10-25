# Verification — 1.1.4 (build 13)

Targeted validation on 2026-10-25 covers the first-launch monitor startup fix.
The release product Swift sources and resources match the tested development
snapshot; version/build metadata and release documentation changed afterward.

- AutoSwitchApp.swift SHA-256: `7af01ebd22cfe27e4080327249f4fb2acd15c69a696623b94b89b36427e25160`.
- GlobalKeyboardMonitor.swift SHA-256: `f51e2c23c8cf9b8ccc7b8dea1b68f977895d9357743e1a597aea865088445fcc`.
- A deterministic baseline reproduced two overlapping tap creations in the old
  monitor. The new lifecycle regression passed six groups covering 101 start
  requests, cancellation during creation, restart, creation/source failures,
  repeated stop/start and permission grant/revocation without onboarding completion.
  It uses real threads/run loops and fake event taps/permission checks.
- The existing six permission-onboarding control-flow scenarios passed.
- The development Debug XCTest run passed 40 tests, skipped two tests requiring
  additional installed Latin layouts, and reported zero failures. Release build
  succeeded. The language-decision and text-injection behavior is unchanged.
- On the maintainer's Apple Silicon Mac, app preferences and its Accessibility
  approval were reset. The locally signed candidate launched with access denied.
  Granting Accessibility created exactly one tap in the same logged second,
  without restarting or clicking Start Using. The maintainer physically typed
  the Hebrew-layout keystrokes for hello and confirmed correction to hello.
  The log recorded five source characters/keystrokes, an accepted decision and
  injection. The onboarding-completion setting remained false, and Input
  Monitoring was observed with No Items after this test.
- The manual diagnostic candidate contained additional logs of lengths and
  decisions only. These temporary diagnostics are excluded from release sources.

This validates the permission-transition scenario on the tested existing account.
It does not prove a never-used Mac/VM installation, Intel runtime execution or
broad secure-field/focus coverage. See TESTING.md for the remaining checklist.
The historical failure's duplicate taps were observed, but their contribution
cannot be reconstructed completely from its original operational log.

The final universal app and DMG still require Developer ID verification,
Apple notarization, stapling and Gatekeeper assessment before publication.
Release notes record the final distribution results once completed.

## Correction to historical 1.1.2 evidence

The earlier claim that AutoSwitch registered itself in Input Monitoring without
manual addition was incorrect. The maintainer reported adding it with the plus
button. Its later presence in that list did not prove automatic registration.
Version 1.1.3 removed the separate permission step; 1.1.4 fixes startup while
retaining Accessibility as the only requested permission.
