# Validation record

Checks completed **4 November 2026**, separately from the historical 2025 demos.
Commands are in [setup](SETUP.md); maintenance changes are recorded in
[provenance](../PROVENANCE.md).

## Environment and builds

Local checks used an Apple silicon Mac on **macOS 15.5**, **Xcode 16.4 (16F6)**
and iOS/Simulator **18.5 SDKs**. The app targets iOS 18.2.

| Check | Result |
| --- | --- |
| Model verification | All four retained manifest entries passed SHA-256 and size checks. |
| Simulator Release | arm64 and x86_64 builds passed, including after maintenance. |
| Device Release | Unsigned baseline compilation passed; signed builds passed before and after maintenance. |
| Bundle inspection | Both retained models and the Metal library present; excluded speed model and private profiling CSV absent. |
| Hosted CI | [GitHub Actions run](https://github.com/OliverPaver/adas-ios/actions/runs/41941653242) passed model verification and Simulator Release on `macos-15` with Xcode 16.4. It did not run tests. |

## Tests

After maintenance, `xcodebuild clean test` passed **16 tests, zero failures and
zero skips** on an **iOS 18.2 iPhone 16 Pro Simulator**, using Debug, normal local
Simulator signing and `-parallel-testing-enabled NO`.

| Suite | Passed |
| --- | ---: |
| `LaneDepartureManagerTests` | 6 |
| `LaneDetectorTests` | 6 |
| `LiveProcessorTests` | 3 |
| `Video_Lane_TestTests` | 1 |

Corrected departure fixtures exercise the unchanged calibration, debounce and
learned-width logic. Integration checks exercised bundled/uniform images, a sample
buffer and missing-camera start/stop. The placeholder `example` has no assertion;
some other assertions are unconditional, and ML checks use fixed waits. **UI tests
remain disabled** and are outside the count. No coverage metric is reported.

## Physical-device checks

The signed Release app was installed and launched on an **iPhone 16 Pro Max,
iOS 27.0.1 (24A446)**, using a separate identifier to preserve the existing app.
Installation and launch succeeded again after maintenance; the process remained
present at a subsequent check.

On the **pre-maintenance baseline**, the owner confirmed live preview, the
navigation stop control returning to search, and advancing imported video with
lane overlays. These manual checks were not repeated during the maintained app's
automated installation/launch check. No input-file identity was collected.

Build warnings remain. These checks establish compilation and the stated behavior,
not detection accuracy, throughput, warning correctness or long-session stability.
See [limitations](LIMITATIONS.md) and [demo provenance](DEMO.md).
