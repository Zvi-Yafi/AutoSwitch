# Changelog

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
