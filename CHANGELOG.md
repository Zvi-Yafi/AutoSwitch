# Changelog

## 1.1.4 — 2026-10-25

- Start keyboard correction automatically after Accessibility access is granted,
  even before completing or after closing the onboarding guide. Retry monitor
  creation after transient failures without requiring an app restart.
- Prevent overlapping starts from creating duplicate keyboard event taps. Cancel
  pending starts safely and clean up each monitor session when stopped.
- Add regression coverage for concurrent starts, cancellation, retries and
  permission transitions. Accessibility remains the only requested permission.

## 1.1.3 — 2026-10-25

- Require only Accessibility permission for keyboard monitoring and correction;
  remove the separate Input Monitoring onboarding step, requests and status gate.
- Open populated settings after onboarding and on later launches. Route Settings
  and Command-comma to the settings window and restore it when reopening the app.
- Update English and Hebrew permission guidance and focused onboarding coverage.

## 1.1.2 — 2026-10-25

- Prefer a complete dictionary-backed translation of a token containing an edge
  apostrophe or Hebrew geresh before validating the source without that mark.
  For example, `׳יט` can now become `why` immediately. Confidence thresholds,
  ignored words and ambiguity between different complete translations still apply.
- Request Input Monitoring access whenever permission is missing, including the
  denied state. Coalesce overlapping requests and open privacy settings after the
  request returns, replacing the fixed-delay fallback. Cancel pending settings
  navigation when onboarding closes.
- Add isolated regression coverage for both changes and update the existing
  geresh translation expectation.

## 1.1.1 — 2026-10-15

- Request Input Monitoring registration when permission onboarding appears, so
  AutoSwitch can be listed in macOS privacy settings on first launch.
- Request permission off the main thread to keep onboarding responsive.
- Handle granted, denied and pending permission states before opening Input
  Monitoring settings, with a fallback when registration remains pending.

## 1.1.0 — 2026-10-11

- Sign the universal macOS app with Developer ID and complete Apple notarization for
  direct distribution from GitHub.
- Require an explicit signing identity and expected Apple team in release scripts.
- Include the required Info.plist in source control, even when local Git settings
  ignore plist files; align the Xcode project with version 1.1.0, build 9.
- Retain the beta's application behavior and MIT license.

## 1.1.0 beta 1

- Clean macOS source publication with the current language-decision improvements.
- Remove personal build identifiers, development-team settings and temporary instrumentation.
- Disable word-level diagnostics in production builds; add privacy regression tests.
- Universal Apple Silicon/Intel packaging and neutral application identifier.
- Separate local-test signing from Developer ID distribution and notarization.
- Source, documentation and downloads now belong in one repository.

This beta is for manual testing. It is not notarized by Apple.
