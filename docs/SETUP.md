# Setup and first run

## Requirements

Use a Mac with full Xcode and Python 3 for the model verifier. The verified
local environment is Apple silicon, Xcode **16.4 (16F6)** and the iOS 18.5 SDK;
the app targets **iOS 18.2+**. Live capture requires a physical iPhone's rear
camera. Map search, routing and imagery require network access; inference is local.

No CocoaPods, Carthage or Swift Package installation is needed. TensorFlow and
coremltools are historical conversion dependencies, not build requirements.
Both models are included; [MODELS.md](MODELS.md) describes their provenance.

## Verify and build

From the repository directory:

```bash
xcodebuild -version
python3 scripts/verify_models.py
bash scripts/build.sh simulator
open Video_Lane_Test.xcodeproj
```

The script builds unsigned Simulator Release into the ignored `DerivedData/`
directory. To choose another output directory or check device-SDK compilation:

```bash
ADAS_BUILD_ROOT=/tmp/adas-ios-build bash scripts/build.sh simulator
bash scripts/build.sh device
```

An unsigned device build cannot be installed on an iPhone. Select the
**Video_Lane_Test** scheme in Xcode. Its Run action uses **Release with the debugger
disabled**; Test uses Debug. For interactive debugging, select Debug and enable
the debugger in your local Run settings.

Xcode generates the `LaneNet`, `LaneNetInput` and `Stop_sign_test3` interfaces,
compiles the Metal library and generates Info.plist from project settings.

## Physical iPhone signing

1. Connect and unlock the phone; trust the Mac and enable Developer Mode if prompted.
2. In **Signing & Capabilities**, select your team for the application and test targets.
3. Replace `org.example.ADAS-iOS` and the test identifiers with identifiers unique
   to your account. Repository development-team settings are intentionally blank.
4. Select the phone as the destination and run.

Keep personal signing settings, certificates and provisioning profiles out of commits.

## Try the application

For recorded input, put a short landscape road video into Photos. On a booted
Simulator, import it with:

```bash
xcrun simctl addmedia booted /absolute/path/to/road-video.mp4
```

Open **Video → Select Video**. This mode runs lane processing and departure checks;
it does not run sign or corridor detection. Use unannotated input: repository
demos already contain historical processing output. The importer loads the whole
clip into memory and has no complete replacement/cancellation lifecycle. Reopen
the app between clips.

For stationary live-camera checks, open **Image**, grant location access, search
for a destination, select it and tap **Go**. Grant camera access when prompted.
The navigation stop control stops capture. **Current Speed** displays Core Location
speed in mph. Stop-sign detection runs, but its visible indicator is disabled.
See [LIMITATIONS.md](LIMITATIONS.md) for interpretation of warnings.

## Tests

List available Simulators and choose one running iOS 18.2 or later:

```bash
xcrun simctl list devices available
```

Replace `SIMULATOR_ID` below. Use normal Simulator signing; no personal team is required.

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

All 16 enabled tests passed locally; UI tests remain disabled. See
[VALIDATION.md](VALIDATION.md) for the environment, suite breakdown and limitations.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Missing model class | Run the verifier; preserve LaneNet's manifest, specification and `weights/weight.bin` in the app folder. |
| Missing Metal function | Preserve all three `.metal` files and their kernel names. |
| No camera in Simulator | Use a physical iPhone for rear-camera capture. |
| Route unavailable | Check permission, network and location fix; Simulator may need a simulated location. |
| Incorrect video orientation | Use landscape input; the importer ignores the track's preferred transform. |
| No lane overlay | Suitable markings may be absent or rejected; raw frames can display while inference runs. |
| Signing fails | Select your team and unique identifiers; the CLI build is unsigned. |
