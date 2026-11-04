# Limitations and validation scope

This repository presents the original university prototype and its implementation choices. The source combines substantial computer-vision and mobile engineering work, but it does not establish validated driving assistance, collision prediction or reliable operation across road conditions. The behavior below is documented so demonstrations and future improvements can be assessed accurately.

## Feature boundaries

| Area | Current boundary |
| --- | --- |
| Live camera | Runs lane processing, departure logic, stop-sign detection and an experimental human/animal corridor test. |
| Selected video | Runs lane processing and departure logic only. |
| Current-speed display | Shows Core Location's speed estimate in miles per hour. Negative reported speed values are clamped to zero. |
| Stop indicator | Detection is implemented; the indicator call is commented out in the navigation UI. |
| Corridor test | Tests object bounding-box bottom-centers against an image-space polygon. It does not estimate distance, motion, collision probability or time-to-collision. |
| Navigation | Provides destination search, a route overlay, location/speed display and off-route recalculation. No spoken turn-by-turn instruction system is implemented. |

## Coordinate and state consistency

**Corridor geometry needs correction and validation.** [`LaneDetector`](../Video_Lane_Test/LaneDetector.swift) stores coefficients in a 512 × 256 image representing the bottom 60% of a frame. [`LaneCollisionManager`](../Video_Lane_Test/LaneCollision.swift) consumes those coefficients and the learned lane width as though they described a full 1280 × 720 frame. It does not apply the crop-offset and scale conversion. Its output should therefore be treated as experimental rather than evidence of correct obstacle localization.

**Asynchronous results can be stale or inconsistent.** Frame buffering and overlay access are protected by a queue, but normal reads and writes of the left/right polynomial properties are not synchronized as one result. Display and departure checks can reuse an older inference, and the two coefficients are not published atomically with the overlay or an inference timestamp.

**Debounce counters count calls, not distinct inferences.** Departure logic can process the same polynomial result repeatedly. Early returns for unavailable boundaries do not reset the departure counter; analogous early returns leave the corridor counter unchanged. Consequently, the configured five- and three-call thresholds do not guarantee consecutive valid observations. The physical meaning of the left/right departure labels also requires a directional fixture check: the current labels follow the sign of lane-midpoint displacement relative to the calibrated image center.

## Algorithm and resource limits

- **Degenerate RANSAC samples can stall processing.** The sampling loop retries until it has a full batch of solvable four-point cubics, without an attempt limit. A cluster with fewer than four distinct x coordinates cannot produce a valid sample. The two-second background timeout clears state but does not cancel this work.
- **Clustering has custom semantics.** Non-core points remain unassigned, propagation stops after ten passes, and threads read and update the same label buffer in a pass. There is no convergence check or guarantee of equivalence to conventional DBSCAN. The all-pairs neighborhood checks also grow quadratically with the retained point count.
- **The polynomial and thresholds are image-space assumptions.** Fitting y as a function of x can be problematic for near-vertical lanes. The pipeline has no camera-intrinsic calibration, perspective rectification or physical lane-width estimate. Crop, fitting and departure constants are fixed.
- **Processing has no complete cancellation lifecycle.** Each lane detector starts an indefinite polling loop. Stopping camera capture does not stop that loop, and a timed-out pipeline can overlap subsequent work.
- **GPU resources are recreated during processing.** Metal devices, command queues and compute pipeline states are created inside drawing, clustering and RANSAC methods. `CIContext` is also created per frame. The source does not implement constructor-level caching of these resources.
- **Model failures and tensor assumptions need stronger handling.** LaneNet load failure triggers `fatalError`; a stop-model load failure disables that detector through an optional model. Output conversion assumes the expected Float32 tensor shapes and contiguous layout. Some GPU allocation failures are not fully checked before pointer use.

These are source-level findings, not measured performance results. The parameter values and algorithms are retained so any later repair can be evaluated against a clear baseline.

## Media and recognition limits

The camera path forces an image orientation and aspect-fills to 1280 × 720. The video path does not apply the track's preferred transform, and frame scheduling uses a fixed delay rather than media timestamps. Different orientations and recording formats therefore require explicit testing.

Video selection loads the entire recording into memory and writes it to a fixed temporary filename. The reader does not provide an explicit cancellation/reset boundary for replacing a video. Long recordings and rapid reselection need lifecycle and memory checks.

Stop-sign detections do not include a general tracking or multi-frame confirmation system. Vision's animal request is an Apple-provided recognizer, not a custom model for every possible road animal.

## Interpreting demonstrations and measurements

A recorded demo shows behavior on that input and device. It does not establish detection accuracy, robustness, generalization or safe on-road behavior. The per-stage timing logs and 33 ms video scheduling delay do not establish end-to-end throughput or inference at 30 FPS.

For reproducible evaluation, record the device, OS/Xcode versions, build configuration, model hashes, input clip and orientation, and measurement boundaries. Separate inference time, full lane-pipeline time, displayed-frame rate and result age. Accuracy claims require labeled data, a defined metric and a documented evaluation split. No such results should be inferred from the presence of detector classes or test files.

## Improvements that preserve the baseline

First establish controlled video fixtures and device behavior. Resource caching, clearer error reporting, bounded work and explicit lifecycle control can then be reviewed separately from algorithm changes. Coordinate conversion and synchronized inference results need focused correctness checks. Changes to clustering semantics, fitting direction, thresholds or calibration rules should be presented as new experiments, with the original implementation available for comparison.
