# Known limitations

This is the original university research prototype, with the maintenance changes
listed in [PROVENANCE.md](../PROVENANCE.md). It has not been validated as a
road-safety system or evaluated for current accuracy or throughput benchmarks.

## Coordinate and state consistency

- **Corridor geometry:** lane coefficients describe the cropped 512 × 256 model
  image, but the human/animal corridor code treats them as full-frame 1280 × 720
  coordinates. That conversion needs correction before interpreting its output.
- **Result synchronization:** overlays and left/right coefficients are read
  separately. Display and warning checks may reuse an older inference result.
- **Warning counters:** debounce counts calls, not distinct inferences. Missing
  boundaries do not consistently reset counters, and left/right warning labels
  need a directional fixture check. These thresholds do not establish a fixed
  warning delay.

## Processing and media

| Area | Limitation |
| --- | --- |
| Cubic fitting | Degenerate four-point samples can retry indefinitely. Fitting `y` as a function of `x` also struggles with near-vertical lanes. |
| Clustering | All-pairs neighborhood work, ten in-place propagation passes and unassigned non-core points differ from converged standard DBSCAN. |
| Lifecycle | The two-second wait timeout does not cancel processing; detector loops continue beyond capture shutdown and work can overlap. |
| Resources and failures | GPU resources and image contexts are repeatedly created. Model/tensor assumptions and allocation failures need stronger handling; LaneNet load failure is fatal. |
| Orientation and playback | Camera orientation is forced; video import ignores the track's preferred transform and schedules reads with a fixed delay rather than media timestamps. |
| Video selection | The importer loads the whole clip into memory and lacks a complete cancellation/reset path when another clip is selected. Start with short landscape clips. |

Lane geometry has no camera-intrinsic calibration, perspective rectification or
physical lane-width estimate. The crop and thresholds remain fixed.

## Feature and evaluation boundaries

The stop detector runs, but its visible indicator is disabled. Human/animal checks
are an experimental corridor-occupancy heuristic, without distance or time-to-collision
prediction. Imported-video mode runs only the lane pipeline and departure logic.
Navigation uses Apple services and has no spoken turn-by-turn system.

The historical clips and passing tests do not establish road robustness or
comprehensive coverage. For future work, prioritize synchronized results, coordinate
conversion, bounded processing and cancellation. Evaluate algorithm or threshold
changes separately against the preserved baseline. See [VALIDATION.md](VALIDATION.md)
for the checks actually completed.
