# Processing parameters

The original implementation keeps its parameters in Swift and Metal source. This page records their current values; it is not a runtime configuration interface or a recommendation for other cameras and datasets. Pixel values refer to the 512 × 256 model image unless stated otherwise.

## Lane inference and post-processing

Source: [`LaneDetector.swift`](../Video_Lane_Test/LaneDetector.swift), [`DBSCANKernel.metal`](../Video_Lane_Test/DBSCANKernel.metal) and [`CubicRANSACKernel.metal`](../Video_Lane_Test/CubicRANSACKernel.metal).

| Parameter | Value | Role |
| --- | --- | --- |
| Bottom crop ratio | `0.60` | Retain the lower 60% of the frame. |
| Model image size | `512 × 256` | Resize the crop without preserving its aspect ratio. |
| RGB normalization | `(value - 127.5) / 127.5` | Convert 8-bit channels to approximately `[-1, 1]`. |
| Binary-mask threshold | `> 0.5` | Select lane pixels. |
| Morphology kernel | `5 × 5` | Dilation followed by erosion. |
| Minimum component area | `100` pixels | Remove smaller eight-connected components. |
| Embedding dimensions | `4` | Values gathered for each retained pixel. |
| Clustering radius | `0.35` | Strict squared-distance comparison in embedding space. |
| Minimum core-point neighborhood | `800` points | Neighborhood count includes the point itself. |
| Label-propagation passes | `10` | Fixed number of GPU passes. |
| Ego-cluster lower-region boundary | `Int(0.65 × height)` | Use points at or below this row to estimate a cluster's mean x. |
| RANSAC hypotheses / batch | `200 / 50` | Target number of valid cubic models and number scored together. |
| RANSAC inlier residual | `< 3.0` pixels | Absolute vertical residual from the cubic. |
| Background pipeline wait | `2.0` seconds | Timeout of the wait; does not cancel the pipeline. |
| Idle polling interval | `0.01` seconds | Sleep when no frame is pending. |

The declared morphology kernel is:

```text
0 0 1 0 0
0 1 1 1 0
1 1 1 1 1
0 1 1 1 0
0 0 1 0 0
```

## Departure and corridor state

Sources: [`LaneDeparture.swift`](../Video_Lane_Test/LaneDeparture.swift) and [`LaneCollision.swift`](../Video_Lane_Test/LaneCollision.swift).

| Parameter | Value | Role |
| --- | --- | --- |
| Departure domain | `512 × 256` | Coordinates of the lane polynomials. |
| Look-ahead rows | `200`, `180` | Search the fitted curves for lane positions. |
| Initial center x | `256` | Starting image-space vehicle-center estimate. |
| Stable midpoint tolerance | `< 20` pixels | Qualify width updates and center calibration. |
| Calibration count | `20` calls | Calibrate after qualifying stable calls. |
| Width-history capacity | `10` samples per buffer | Both buffers receive the same averaged width. |
| Polynomial y-search tolerance | `≤ 7` pixels | Accept the nearest sampled x when solving for a target y. |
| Departure offset limit | `0.4 × half lane width` | Equivalent to 20% of the estimated lane width. |
| Departure debounce | `5` qualifying calls | Subject to the stale-result and reset limitations. |
| Corridor domain | `1280 × 720` | Currently differs from the supplied polynomial domain. |
| Corridor top/bottom rows | `360`, `720` | Corners of the occupancy polygon. |
| Corridor polynomial y-search tolerance | `< 5` pixels | Accept the nearest sampled x. |
| Corridor debounce | `3` qualifying calls | Human/animal occupancy confirmation counter. |

## Capture, signs and navigation

| Parameter | Value | Source |
| --- | --- | --- |
| Camera preset / output image | `1280 × 720`, where supported | [`LiveProcessor.swift`](../Video_Lane_Test/LiveProcessor.swift) |
| Stop-sign processing cadence | Every third captured frame | [`LiveProcessor.swift`](../Video_Lane_Test/LiveProcessor.swift) |
| Stop-sign label / confidence | `"3"` / `≥ 0.5` | [`StopSignDetector.swift`](../Video_Lane_Test/StopSignDetector.swift) |
| Video inter-read delay | `0.033` seconds | [`VideoProcessor.swift`](../Video_Lane_Test/VideoProcessor.swift) |
| Destination-search debounce | `0.3` seconds | [`MapViewModel.swift`](../Video_Lane_Test/Maps/MapViewModel.swift) |
| Off-route threshold | `> 50` metres from route polyline | [`MapViewModel.swift`](../Video_Lane_Test/Maps/MapViewModel.swift) |

See [architecture](ARCHITECTURE.md) for how these values interact and [limitations](LIMITATIONS.md) for assumptions that should accompany any experiment changing them.
