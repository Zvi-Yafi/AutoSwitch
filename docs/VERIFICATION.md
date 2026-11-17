# Verification — 1.1.7 (build 16)

Targeted validation on 2026-11-17 covers a deferred ambiguous word being added
to a later correction after the original word was deleted. The QA candidate
uses public commit `0adc0fbd098cb825bdf04ceed5ac9954d4f101da` with these two
product files replaced:

- AutoSwitchStateMachine.swift SHA-256:
  `6ba8402b954921182f133ee4af3ee89ae195a0c55d192d7d9c3e7399fb04dc75`.
- GlobalKeyboardMonitor.swift SHA-256:
  `7d55f209b5366097490ca49d98c0b384ad232a05602ed79ec10e10646f837fa8`.

All 22 product Swift/resource files match the tested candidate. Version/build
metadata and release documentation change after candidate QA.

- All 26 deletion scenarios passed. The runner compiles the production state
  machine, buffer, history, models and keyboard callback with in-memory services
  and deterministic queues. Against unchanged 1.1.6, the same expectations failed
  in 15 scenarios (45 assertions), including restoration of an erased word and
  late results affecting new text. This checks edit lifetimes and control flow,
  not actual GCD scheduling, layout mapping or operating-system event delivery.
- The existing 27 isolated Spotlight injection scenarios passed.
- Debug XCTest executed 40 tests, two skipped, zero failures. Release XCTest
  executed 35 tests, two skipped, zero failures. The skipped cases need additional
  Latin layouts. Bulk word evaluation and efficiency benchmarks were excluded.
  Test preferences and logs used a separate temporary home directory.
- Xcode Release built arm64 and x86_64 with minimum macOS 13. The candidate's
  local Developer ID signature passed strict verification. The process path
  confirmed the temporary candidate, and its UI reported correction active with
  ambiguity enabled. Existing permissions were retained for QA.
- The maintainer physically confirmed three scenarios in a new TextEdit document:
  deletion of a deferred word followed by correction without the erased prefix,
  word/selection deletion followed by clean correction, and immediate Undo.
  These typing results are maintainer confirmations. The UI tool timed out when
  opening TextEdit, so there are no independently captured final-text screenshots.
- Actual Intel/macOS 13 execution, a new-machine installation and broad secure
  field coverage were not verified. Focus checks and asynchronous keyboard
  delivery are not atomic.

Final distribution still requires Developer ID verification, Apple notarization,
stapling, Gatekeeper assessment and public-download checksum verification.
Release notes record those results after completion.

---

# Historical verification — 1.1.6 (build 15)

Targeted validation on 2026-11-10 covers Spotlight leaving a source character
after correction on Space. The candidate uses public commit
`a0e26a1febcfd43c61b3952908065351de59db03` with these two product files replaced:

- TextInjector.swift SHA-256:
  `3573193b0645dba4752e0c9a3369362ced0021834545289d20989c4485d435c9`.
- AutoSwitchStateMachine.swift SHA-256:
  `372a67afaef71d5abe6c9879193363399553934e5e222251ee99871ff38d4a2f`.

All other product Swift sources and resources match the public baseline.
Version/build metadata and release documentation change after candidate QA.

- On macOS 27.0.1, UI inspection identified SpotlightSearchField in the Siri host
  (com.apple.campo). A new regression failed against the previous host detection
  and passed after adding this specific field. Other Siri fields are excluded.
- All 27 isolated injection scenarios passed. The actual TextInjector class runs
  with rebound AX/keyboard/scheduling services and real AXValue/CFRange bridging;
  these tests do not simulate the operating system's actual event delivery.
- Debug XCTest executed 40 tests, two skipped, zero failures. Release XCTest
  executed 35 tests, two skipped, zero failures. Skips require additional Latin
  layouts. Bulk word evaluation and efficiency benchmarks were excluded. Test
  preferences and logs used a separate temporary home directory.
- Xcode Release built arm64 and x86_64 targeting macOS 13. The local candidate's
  Developer ID signature passed strict verification. Its process path and active
  Accessibility permission/event tap were confirmed; existing permissions were
  retained and the installed 1.1.5 app was preserved.
- The maintainer reproduced the leftover character with installed 1.1.5, then
  physically repeated the same query twice with the candidate and confirmed the
  corrected word without a leftover character. The maintainer also confirmed
  immediate Undo, preservation of a numeric query prefix, and correction in a
  new TextEdit document. These typing results are maintainer observations, not
  independently captured screenshots of the final text.
- No actual Intel/macOS 13 execution, clean-machine installation or broad secure
  field coverage was performed. Focus checks cannot make asynchronous keyboard
  delivery atomic. Unsupported AX ranges retain the keyboard fallback only while
  the original focused element can still be confirmed.

The final distribution still requires Developer ID verification, Apple
notarization, stapling, Gatekeeper assessment and download checksum verification.
Release notes record those results after completion.

---

# Historical verification — 1.1.5 (build 14)

Targeted validation on 2026-10-25 covers the duplicate-settings-window fix.
The tested scaffold was public commit `df8b9ba863277150777214814b961f5c6e324785`
with only AutoSwitchApp.swift replaced. Its SHA-256 is
`d3a432374edede9e3617e4abd029746283dfdd57719e49c136aaeafb10c5d2f1`.
The release uses these same product sources and resources; only version/build
metadata and release documentation change after QA.

- Xcode Release built arm64 and x86_64 with minimum macOS 13.0.
- The Debug XCTest regression selection passed 40 tests, with two skipped because
  additional Latin keyboard layouts were unavailable, and zero failures. Bulk
  word evaluation and efficiency benchmarks were excluded.
- Fourteen geresh-policy, six permission-onboarding and six monitor-startup
  regression scenarios passed. No new test files were added for this release.
- The previous installed app was removed and all com.autoswitch.app permissions
  reset. The locally Developer ID signed candidate launched with one setup guide.
  Granting Accessibility started exactly one keyboard tap without restarting.
- The maintainer confirmed one populated AutoSwitch Settings window and one menu
  bar icon after repeated Command-comma, close/reopen from the menu bar,
  minimize/Settings and reopening from Applications. No separate General window
  appeared. These UI checks were confirmed by the maintainer because the native
  UI inspection tool could not read or screenshot the settings window.
- The maintainer physically typed the Hebrew-layout keystrokes for hello and
  confirmed correction to hello. Input Monitoring was independently observed as
  No Items. Operational logs showed one tap and ten received events.
- Settings serialization round-trip is covered by XCTest. Visual persistence
  editing, actual Intel/macOS 13 execution, a new-machine/VM install, and broad
  secure-field/focus coverage were not verified in this targeted run.

The final universal app and DMG require Developer ID verification, notarization,
stapling and Gatekeeper assessment before publication. Release notes record the
final distribution results. See TESTING.md for the remaining broader checklist.

---

# Historical verification — 1.1.4 (build 13)

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
