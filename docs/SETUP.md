# Setup and first run

## Requirements

| Item | Requirement / verified environment |
| --- | --- |
| Build host | macOS with full Xcode; the Command Line Tools package alone is insufficient |
| Verified toolchain | Xcode 16.4, build 16F6; iOS 18.5 SDK; Apple silicon Mac |
| Deployment target | iOS 18.2 or later; project declares iPhone and iPad families |
| Camera demonstration | A physical iPhone with rear camera and a suitable iOS version |
| Model artifacts | All files listed in `MODEL_MANIFEST.json` |
| Python | Python 3, used only by the checksum verifier |
| Network | Map search, routing and map imagery use Apple services; ML inference is local |

No CocoaPods, Carthage or Swift Package installation is needed for this app.
TensorFlow and coremltools are historical conversion dependencies, not runtime
or Xcode build requirements. Recreating model training/conversion is a separate,
currently incomplete process described in [MODELS.md](MODELS.md).

## Verify and build

Open a terminal in the repository directory:

```bash
xcodebuild -version
python3 scripts/verify_models.py
bash scripts/build.sh simulator
```

The script performs an unsigned Release build for the generic iOS Simulator
destination. Build products go to the ignored `DerivedData/` directory. Set
`ADAS_BUILD_ROOT` to use a different directory:

```bash
ADAS_BUILD_ROOT=/tmp/adas-ios-build bash scripts/build.sh simulator
```

To check device compilation without using signing credentials:

```bash
bash scripts/build.sh device
```

An unsigned device build cannot be installed on an iPhone. It verifies compilation
for the iOS device SDK. Consult [VALIDATION.md](VALIDATION.md) for the checks actually
completed on this snapshot.

## Open in Xcode

```bash
open Video_Lane_Test.xcodeproj
```

Select the **Video_Lane_Test** scheme. The project, module and scheme keep their
original names. The shared scheme runs **Release with the debugger disabled**;
its Test action uses Debug. For interactive debugging, change the Run action to
Debug and enable the debugger in your local scheme settings.

Xcode should generate the `LaneNet`, `LaneNetInput` and `Stop_sign_test3`
interfaces from the two included models and compile the `.metal` files
into the default library. There is no standalone checked-in Info.plist:
the build generates it from project settings.

## Physical iPhone signing

1. Connect and unlock the iPhone; trust the Mac if prompted. Enable Developer Mode
   on the phone if Xcode requests it.
2. In Xcode's **Signing & Capabilities**, select your own team for the application
   and test targets. The repository intentionally has no personal development team.
3. Replace the `org.example.ADAS-iOS` application identifier with an identifier
   unique to your account. Give the test targets corresponding unique identifiers.
4. Select the physical phone as the destination and run the application.

Signing changes are local to your checkout. Do not publish certificates,
provisioning profiles, private keys or device identifiers.

## Recorded-video walkthrough

1. Put a landscape road video that you own or may use into the device's Photos
   library. On a booted simulator, a local clip can be imported with:

   ```bash
   xcrun simctl addmedia booted /absolute/path/to/road-video.mp4
   ```

2. Open the **Video** tab and tap **Select Video**.
3. Select the clip. The application extracts frames, computes lane overlays and
   publishes lane-departure state.

This path does not run sign detection or human/animal corridor checks. It does
not export a processed video or provide a timestamp-synchronized player. Select
short clips initially: the importer currently loads the complete video into memory.
Avoid replacing a selected clip while it is processing until cancellation behavior
has been improved. Force-quit and reopen the app to reset the current session.

The repository demonstration is already-processed historical output. It is a
visual reference, not an unannotated evaluation input. The included test image is
used by the original tests; its TuSimple/Apache 2.0 attribution is recorded in
[third-party notices](../THIRD_PARTY_NOTICES.md#tusimple-source-and-test-fixture).

## Navigation and live camera

1. Open the **Image** tab, which contains the map/navigation interface.
2. Grant location permission, search for a destination and choose a result.
3. Tap **Go**. The live camera view appears while navigation is active; grant
   camera access if prompted.
4. Stop navigation to stop the capture session.

The live pipeline runs lane processing and departure checks, stop-sign detection
every third camera callback, and experimental human/animal corridor checks. The
visible stop-sign indicator is disabled in the current UI. The **Current Speed**
readout uses Core Location and displays miles per hour. Use
[LIMITATIONS.md](LIMITATIONS.md) to interpret the output. Recorded-input or
stationary demonstrations are appropriate for evaluating this research prototype.

## Tests

List available simulator devices and select one running iOS 18.2 or later:

```bash
xcrun simctl list devices available
```

Use its identifier in the command below, replacing `SIMULATOR_ID`:

```bash
xcodebuild \
  -project Video_Lane_Test.xcodeproj \
  -scheme Video_Lane_Test \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath DerivedData \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 45 \
  -maximum-test-execution-time-allowance 60 \
  test
```

All 16 enabled tests passed on an iOS 18.2 Simulator with Xcode 16.4 after correcting
the departure fixtures and expectations against the unchanged implementation.
The test command uses normal local Simulator signing; no personal development team
is required. Several integration tests still use fixed delays, and some assertions
are unconditional, so this result does not establish comprehensive coverage or
model accuracy. Read [VALIDATION.md](VALIDATION.md) for scope and results. The
original shared test plan disables UI tests.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Model class is missing | Verify model files, including LaneNet's manifest and `weights/weight.bin`; confirm they remain in the synchronized app folder |
| Metal function cannot be found | Preserve all three `.metal` files and their original kernel names in the app target |
| No camera in Simulator | A physical rear-camera feed is required; the no-camera configuration path now commits correctly and passes the start/stop smoke test |
| Route is unavailable | Check location permission, a location fix and network access; Simulator may need a simulated location |
| Video orientation looks incorrect | The importer does not apply the track's preferred transform; use a landscape input and document its orientation |
| No lane overlay | The model may not identify suitable markings, or post-processing may reject them; the UI can display a raw frame while inference runs |
| Signing fails | Set your own team and unique identifiers; unsigned CLI builds are compilation checks only |

Do not change lane thresholds merely to make an example appear successful. Record
the input, device, orientation and configuration when reporting a result.
