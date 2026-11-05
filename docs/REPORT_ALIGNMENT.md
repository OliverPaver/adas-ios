# Design notes and dissertation alignment

This application accompanies Oliver Paver's 2025 BSc Computer Science dissertation,
*Advanced Dynamic Road Hazard Detection with Navigation on a Mobile Platform*,
The University of Manchester, supervised by Dr Terrence Morley. The dissertation
provides the original motivation and development narrative. This repository's
technical descriptions follow the retained source and model artifacts where a
historical description differs from the implementation.

The report is not bundled in this repository. References below use its printed
page numbers, which match the one-based PDF page positions in the supplied final
copy. They are included so a reader with the report can follow the design history.

## Project motivation

The project investigates an accessible mobile platform for combining navigation
with road perception, using an iPhone's camera, on-device inference and graphics
APIs. Its objectives bring together static sign recognition, dynamic lane geometry,
warning logic and a usable navigation interface. This is an engineering research
prototype; the objectives are not evidence of accident reduction or driving safety.

The central implementation work lies between a network prediction and an
application-level result. A lane mask alone does not identify the vehicle's two
lane boundaries. Pixel embeddings must be grouped into instances, plausible
boundaries selected, curves fitted and results transformed back to the displayed
image. The live application then has to coordinate those results with capture,
location updates and interface state.

## Engineering choices

| Choice | Role in the retained implementation |
| --- | --- |
| Segmentation plus instance embeddings | LaneNet supplies lane/non-lane output and four embedding values per pixel. Clustering groups retained pixels into lane candidates instead of treating the whole mask as one curve. |
| Mask cleanup before clustering | Morphology and small-component removal reduce fragmented mask regions before embedding-space processing. No measured accuracy improvement is claimed for this snapshot. |
| CPU/GPU division of work | CPU code prepares data and solves/refines cubics. Metal performs neighborhood/label work, scores batches of hypotheses and writes overlay points. Rendering also contains CPU rasterization and composition. |
| Robust cubic fitting | RANSAC selects a hypothesis using inlier support, then least squares refines that inlier set. The model represents curved image-space boundaries; it is not a calibrated 3D road model. |
| A single pending frame | New input can replace work that has not started, while the UI reuses the latest overlay. This constrains queued input, not the age of every displayed result or the lifetime of processing work. |
| Native iOS services | AVFoundation, Core ML, Vision, Metal, MapKit and Core Location provide the application interfaces. Training/conversion are separate from inference; map search and directions use Apple services. |

See [architecture](ARCHITECTURE.md) for runtime flow and source mapping, and
[configuration](CONFIGURATION.md) for the unchanged constants.

## Reading the report alongside the code

| Report reference | Corresponding source | What this repository states |
| --- | --- | --- |
| Abstract, p. 5; §§1.1–1.2, pp. 7–8 | Application as a whole | A smartphone-based navigation and road-perception prototype; intended benefits are distinguished from validated outcomes. |
| §4 and §§4.1.1–4.1.2, pp. 17–18 | `Maps/MapViewModel.swift`, `ContentView.swift` | Destination search, fastest expected-time route selection, route overlay, GPS speed and off-route recalculation. No spoken turn-by-turn system is claimed. |
| §5.2, p. 22; §5.2.3, pp. 24–25 | `StopSignDetector.swift`, `LiveProcessor.swift` | Create ML/Vision stop recognition, label `"3"`, confidence ≥0.5 and processing every third camera callback. The retained UI's stop-indicator invocation is disabled. |
| §6.2, pp. 28–29; §6.6.3.1, p. 44 | `LaneNet.mlpackage`, `LaneDetector.swift` | A 512 × 256 normalized RGB input, binary mask and four-dimensional embeddings. Some earlier narrative descriptions use three dimensions; the actual model contract and §6.6.3.1 specify four. |
| §6.5.3, pp. 35–36 | `DBSCANKernel.metal` | Custom DBSCAN-style core-point clustering, ten label-propagation passes and unassigned non-core points. It is not presented as a converged implementation of standard DBSCAN. |
| §6.5.5, p. 37; §6.5.5.3, p. 39 | `LaneDetector.swift`, `CubicRANSACKernel.metal` | Per-lane cubic hypotheses are sampled/solved on the CPU, scored in batches on Metal and refined on the CPU. GPU scoring does not imply an entirely GPU-resident pipeline. |
| §6.8, p. 47; §§6.8.2–6.8.3, p. 48 | `LaneDeparture.swift` | Image-space width learning, 20-call center calibration and five-call debounce. No physical look-ahead distance or fixed warning latency is inferred from these constants. |
| §6.9, p. 49 | `LaneCollision.swift` | An experimental human/animal corridor test. The current coordinate mismatch prevents treating it as validated collision prediction. |

Source paths in the table are relative to `Video_Lane_Test/`.

## Historical results and current evidence

The dissertation discusses the original development experiments, training and
performance observations. Those numbers have not been promoted to reproduced
benchmarks for this repository. A retained model, historical screen recording or
successful build alone cannot reproduce the original evaluation protocol.

The current source also creates some Metal resources inside processing methods,
uses separate overlay/geometry state and has incomplete cancellation behavior.
Accordingly, the documentation does not claim constructor-cached GPU resources,
fixed end-to-end latency, inference on every displayed frame or a fully offline
application. These limits are detailed in [LIMITATIONS.md](LIMITATIONS.md).

The portfolio adds source documentation, model identities, historical media crops
and the specific maintenance changes recorded in [PROVENANCE.md](../PROVENANCE.md).
It preserves the retained algorithms and their parameters. The
[validation record](VALIDATION.md) contains the build, test and device checks
actually completed; [DEMO.md](DEMO.md) separately identifies the historical footage.
