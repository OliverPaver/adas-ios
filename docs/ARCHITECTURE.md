# Architecture

## Application structure

The “Image” tab combines MapKit navigation with live camera processing; the “Video” tab processes a recording selected from Photos. [`LiveProcessor`](../Video_Lane_Test/LiveProcessor.swift) and [`VideoProcessor`](../Video_Lane_Test/VideoProcessor.swift) each own a `LaneDetector` and `LaneDepartureManager`. Only live capture runs stop-sign and human/animal detection. SwiftUI observes published processor and navigation state.

## Lane pipeline

### Model input and outputs

[`LaneDetector.swift`](../Video_Lane_Test/LaneDetector.swift) crops the bottom 60% of each frame, resizes it to 512 × 256, and normalizes RGB with `(channel - 127.5) / 127.5`.

| Core ML feature | Float32 shape |
| --- | --- |
| `lanenet_input_tensor` | `[1, 256, 512, 3]` (NHWC) |
| `lanenet_final_binary_output` | `[256, 512]` |
| `lanenet_final_pixel_embedding_output` | `[256, 512, 4]` |

Output conversion assumes contiguous memory. Model execution uses Core ML; custom post-processing is split between CPU and Metal.

### Post-processing and fitting

1. **CPU:** threshold the mask, apply vImage dilation then erosion, remove small eight-connected components, and gather retained pixels’ four-dimensional embeddings.
2. **Metal:** identify core points and propagate cluster labels. This custom DBSCAN-style algorithm counts the point itself, leaves non-core points unassigned, and uses ten fixed propagation passes rather than convergence.
3. **CPU:** select the nearest left/right clusters using mean x in the bottom 35% of the model image.
4. **CPU + Metal:** generate random four-point cubic hypotheses on the CPU; score their vertical residuals and count inliers on the GPU; refit the best inliers by CPU least squares. The polynomial is **y = Ax³ + Bx² + Cx + D**.
5. **CPU + Metal:** sample curves and rasterize segments with Bresenham on the CPU; write red/green points into a Metal texture; read back, resize and composite the overlay.

See [processing parameters](CONFIGURATION.md) for thresholds and [`DBSCANKernel.metal`](../Video_Lane_Test/DBSCANKernel.metal) / [`CubicRANSACKernel.metal`](../Video_Lane_Test/CubicRANSACKernel.metal) for GPU stages.

### Coordinate systems

Coefficients remain in the cropped 512 × 256 domain. Overlay placement for frame dimensions `W`, `H` is:

```text
x_frame = x_model × W / 512
y_frame = 0.4 × H + y_model × (0.6 × H) / 256
```

Departure uses model coordinates. The corridor detector instead assumes 1280 × 720 without converting the coefficients; see [limitations](LIMITATIONS.md).

## Frame scheduling and state

`feedFrame` replaces one pending frame and returns the current frame with the latest completed overlay. A background loop processes pending work. Consequently, displayed frames, coefficients and departure checks can reuse earlier inference results. The two-second wait timeout does not cancel dispatched processing. Video reads use a 33 ms delay rather than presentation timestamps; this is not a measured inference rate.

## Departure and object detectors

[`LaneDeparture.swift`](../Video_Lane_Test/LaneDeparture.swift) samples curves at rows 200 and 180, learns lane width and calibrates the center after 20 stable calls. Learned width can reconstruct one missing boundary. An offset above 0.4 times the half-width produces a departure state after five qualifying calls.

Live capture calls [`StopSignDetector.swift`](../Video_Lane_Test/StopSignDetector.swift) every third camera callback, accepting label `"3"` at confidence ≥0.5. Its UI indicator invocation is commented out.

[`LaneCollision.swift`](../Video_Lane_Test/LaneCollision.swift) runs Vision human and animal requests serially, tests bounding-box bottom-centers against a lane polygon, and debounces occupancy over three calls. It does not estimate distance or time to collision.

## Navigation and presentation

[`MapViewModel`](../Video_Lane_Test/Maps/MapViewModel.swift) resolves destination searches, selects the automobile route with the shortest expected travel time, and reroutes beyond 50 m from its polyline. Core Location supplies position and current speed, displayed in mph. “ETA” is travel duration at route calculation. The navigation camera panel’s appearance/disappearance starts/stops capture.

## Framework boundaries

Inference uses bundled models locally; navigation uses Apple location and mapping services. Training and model conversion are outside the application.
