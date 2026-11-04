# Validation record

Validation date: **4 November 2026**. These results describe this source snapshot;
they are separate from the original project's historical demonstration and report.

## Environment

- Apple silicon Mac, macOS 15.5.
- Xcode 16.4, build 16F6.
- iOS / iOS Simulator 18.5 SDKs; app deployment target iOS 18.2.
- Original lane-processing algorithms, Metal kernels, thresholds and model bytes
  retained for the included features. Maintenance covers departure-test corrections,
  balanced capture-session configuration and the author-requested exclusion of
  speed-limit recognition, as recorded in [PROVENANCE.md](../PROVENANCE.md).
- Neutral bundle identifiers and blank development-team settings.

## Checks and outcomes

| Check | Outcome | What it establishes |
| --- | --- | --- |
| Model SHA-256 and size verification | Passed for all four retained manifest entries | LaneNet specification, weights, manifest and the stop-sign model retain their recorded identities |
| Generic Simulator Release build | Passed for arm64 and x86_64, including after maintenance | App source, generated Core ML interfaces, Metal shaders and resources compile with Xcode 16.4 |
| Generic iOS device Release build | Passed, signing disabled, before maintenance | Baseline device-SDK compilation succeeds; this is not an installation or hardware run |
| Signed iPhone Release build | Passed, including after maintenance | Local development signing and provisioning succeeded for a separate installation identifier |
| Debug test-target compilation | Passed after maintenance | App and unit/UI test targets compile with the corrected fixtures and camera configuration |
| iOS Simulator test execution | 16 passed, 0 failed, 0 skipped | All enabled tests passed on an iOS 18.2 iPhone 16 Pro Simulator; UI tests remain disabled by the original test plan |
| Portable departure-logic check | 6 passed, 0 failed after correction | Corrected tests exercise the unchanged departure implementation; original baseline was 2 passed, 4 failed |
| Missing-camera start/stop | Passed in Simulator suite | The capture path reported no rear camera and the start/stop smoke test completed without the uncommitted-configuration exception |
| Release app-bundle inspection | Passed | The two retained compiled models and default Metal library are present; the excluded speed model and private profiling CSV are absent |
| Physical iPhone installation and launch | Passed, including after maintenance | Installed and launched on an iPhone 16 Pro Max running iOS 27.0.1; the launched process remained present at a subsequent check |
| Live camera and navigation stop control | Passed, user-observed before maintenance | The owner confirmed that the live camera and navigation stop control both work after following the stationary navigation walkthrough |
| Imported-video lane walkthrough | Passed, user-observed before maintenance | The owner confirmed that selected-video frames advance and lane overlays appear |
| Historical media review | Completed | Selected excerpts contain actual recorded output and are labelled as historical |
| Hosted GitHub Actions run | Not executed | A build-and-integrity workflow is supplied for future execution |

Builds produce warnings, including deprecated AVFoundation/SwiftUI calls and
redundant Swift expressions. They are retained with the original source. No
warning-free-build, accuracy, frame-rate, test-coverage or road-safety claim is made.

## Build reproduction

From the repository root:

```bash
python3 scripts/verify_models.py
bash scripts/build.sh simulator
bash scripts/build.sh device
```

The build script uses Release, the explicit `Video_Lane_Test` project/scheme, and
`CODE_SIGNING_ALLOWED=NO`. It supports `ADAS_BUILD_ROOT` for an external build
directory. [SETUP.md](SETUP.md) describes signing and installation separately.

The Release app, version 1.0 (build 1), was signed with local development credentials,
installed and launched on an iPhone 16 Pro Max running iOS 27.0.1 (24A446).
The installation used a separate portfolio bundle identifier to preserve the
existing application. A subsequent process listing still contained the launched
process. Personal signing credentials and device identifiers are excluded from
the repository.

After the departure-test and camera-configuration changes and exclusion of
speed-limit recognition, the clean signed Release build, installation and launch
were repeated successfully on the same phone.
The updated process also remained present at a subsequent check. The on-screen
walkthrough below was performed on the baseline; it was not repeated as part of
the later automated launch check.

Before maintenance and feature-scope changes, the owner completed the stationary walkthrough
on the installed baseline and reported:

- **Live camera and navigation stop control:** the camera feed works after entering navigation,
  and the red circular stop control returns to search.
- **Imported video:** selected-video frames advance and lane overlays appear.

These are user-observed functional checks, separate from the automated build and
process checks. No recording or input-file identity was collected for this run.
They do not establish lane accuracy, throughput, sign recognition, warning
correctness, navigation accuracy or long-session stability. The demonstration
assets remain historical footage from 2025.

The supplied [workflow](../.github/workflows/build.yml) checks model identity and
builds the Simulator target using Xcode 16.4 on `macos-15`. It currently performs
build/integrity checks only; the test results here are local runs. The Xcode path
is listed in GitHub's [macOS 15 runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
Hosted-runner availability may change; the locally verified environment is the
one recorded above.

## iOS test results and limits

After applying the approved departure-test corrections, camera configuration
fix and speed-limit recognition exclusion, `xcodebuild clean test` completed
successfully on the iOS 18.2 iPhone 16 Pro
Simulator using Debug, normal local Simulator signing and
`-parallel-testing-enabled NO`. The finalized result bundle reports **16 passed,
zero failed and zero skipped**:

| Suite | Passed tests |
| --- | ---: |
| `LaneDepartureManagerTests` | 6 |
| `LaneDetectorTests` | 6 |
| `LiveProcessorTests` | 3 |
| `Video_Lane_TestTests` | 1 |

The `LiveProcessor` tests exercised the missing-rear-camera path, including
start/stop and a synthetic sample-buffer callback. The lane-detector suite
completed its bundled-image and uniform-image checks. These results do not
establish comprehensive coverage: the placeholder `example` test has no assertion,
some assertions are unconditional, and ML integration tests use fixed waits and
real models. The original shared test plan disables UI tests; disabled UI tests
are not included in the 16-test count. No coverage metric is reported.

### Earlier baseline attempts

An iOS 18.2 Simulator run compiled the test targets and booted a simulator, but
did not produce individual test results during the bounded attempt. It was
interrupted; Xcode then failed to finalize the test-result bundle. This is an
incomplete execution result, not proof of an application-test pass or failure.
A second attempt on a fresh iOS 18.6 simulator, with normal local simulator
signing and only the departure suite selected, also stalled before individual
results and was interrupted. Neither earlier attempt established an iOS test
result. The subsequent completed run above supersedes the earlier incomplete
status; it does not establish the cause of those startup stalls.

## Portable departure check

To separate test-fixture behavior from simulator startup, a temporary macOS Swift
package first ran the original six `LaneDepartureManagerTests` against the original
`LaneDepartureManager` implementation. After correction, the harness was refreshed
from the current candidate and run again. For both runs the adapter changed only:

1. `import UIKit` to `import Foundation` in the test copy, supplying
   `CGFloat` without an iOS runtime.
2. The test module import to the temporary package module.

The implementation already imports Foundation and was copied byte-for-byte.
The package used Swift 5 language mode. No implementation logic or parameter was
changed, and each run retained that version's assertions unchanged by the adapter.
This check covers the platform-independent departure
logic, not camera, Core ML, Metal, UIKit presentation or full iOS integration.

| Test | Original fixture | Corrected fixture |
| --- | --- | --- |
| `testInitialization` | Passed | Passed |
| `testNoLinesResultsInNoDeparture` | Passed | Passed |
| `testSingleLineFallback` | Failed | Passed |
| `testCalibrationAutoCentersAfterStableFrames` | Failed | Passed |
| `testConsecutiveFramesTriggerDeparture` | Failed | Passed |
| `testOffsetReturnsBeforeThresholdConsecutiveFrames` | Failed | Passed |

The original shared fixture used `y = 1000(x − xVal)² + 190`. On the implementation's
integer x grid, its nearest y value is ten pixels from each requested row
(180 and 200), outside the seven-pixel tolerance. Consequently the manager sees
no usable lines. Expectations also assumed 25 calibration calls and eight
departure calls, while the implementation uses 20 and five.

The corrected linear fixtures cross both look-ahead rows at exact integer
coordinates. Assertions now verify the existing 20-call calibration, five-call
debounce, reset behavior and learned-width fallback through observable states.
The original algorithm and thresholds were not changed to satisfy the tests.

## Remaining work

- Strengthen placeholder, timing-dependent and unconditional tests with focused
  behavior and failure-path checks; keep these distinct from accuracy evaluation.
- Validate the coordinate transformation between model-space lanes and full-frame
  corridor detections before interpreting the collision warning.
- Verify orientation, model-result synchronization, cancellation, permissions and
  repeated video selections with controlled inputs.
- Select the author's licence for original work before publication. LaneNet's
  source confirmation and conversion notice, and the TuSimple test-image licence
  and attribution, are recorded in the third-party notices.

See [LIMITATIONS.md](LIMITATIONS.md) for the source-level constraints and
[DEMO.md](DEMO.md) for the historical recording's provenance.
