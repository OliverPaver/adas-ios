# Processing parameters

Constants are defined in source. Pixels use the 512 × 256 model domain unless stated otherwise. Call counts may reuse inference results.

## Lane inference and post-processing

Sources: [LaneDetector.swift](../Video_Lane_Test/LaneDetector.swift), [DBSCANKernel.metal](../Video_Lane_Test/DBSCANKernel.metal), [CubicRANSACKernel.metal](../Video_Lane_Test/CubicRANSACKernel.metal).

| Parameter | Value |
| --- | --- |
| Bottom crop / resize | 60% / 512 × 256, stretched |
| RGB normalization | `(value - 127.5) / 127.5` |
| Mask threshold | >0.5 |
| Morphology | Dilation then erosion; kernel below |
| Minimum eight-connected component | 100 pixels |
| Embedding dimensions | 4 |
| Clustering radius / core neighborhood | 0.35, strict distance / ≥800 including self |
| Label propagation | 10 passes |
| Ego-cluster region | y ≥ `Int(0.65 × height)` |
| RANSAC valid hypotheses / batch | 200 / 50 |
| Inlier vertical residual | <3 pixels |
| Pipeline wait / idle polling | 2 s (no cancellation) / 0.01 s |

Kernel:

```text
0 0 1 0 0
0 1 1 1 0
1 1 1 1 1
0 1 1 1 0
0 0 1 0 0
```

## Departure and corridor state

Sources: [LaneDeparture.swift](../Video_Lane_Test/LaneDeparture.swift), [LaneCollision.swift](../Video_Lane_Test/LaneCollision.swift).

| Parameter | Value |
| --- | --- |
| Departure domain / initial center x | 512 × 256 / 256 |
| Look-ahead rows | 200, 180 |
| Stable midpoint tolerance / calibration | <20 pixels / 20 stable calls |
| Width history | 10 samples each; both buffers receive same averaged width |
| Polynomial y-search tolerance | ≤7 pixels |
| Departure offset limit / debounce | 0.4 × half-width / 5 qualifying calls |
| Corridor domain / top–bottom rows | 1280 × 720 / 360–720 |
| Corridor y-search tolerance / debounce | <5 pixels / 3 qualifying calls |

Corridor coordinates differ from supplied coefficients. See [limitations](LIMITATIONS.md) for coordinate and debounce behavior.

## Capture, signs and navigation

Sources: [LiveProcessor](../Video_Lane_Test/LiveProcessor.swift), [StopSignDetector](../Video_Lane_Test/StopSignDetector.swift), [VideoProcessor](../Video_Lane_Test/VideoProcessor.swift), [MapViewModel](../Video_Lane_Test/Maps/MapViewModel.swift).

| Parameter | Value |
| --- | --- |
| Camera preset / output | 1280 × 720 preset where supported; 1280 × 720 output |
| Stop-sign cadence / label / confidence | Every third callback / `"3"` / ≥0.5 |
| Video inter-read delay | 0.033 s |
| Search debounce | 0.3 s |
| Off-route threshold | >50 m from route polyline |
