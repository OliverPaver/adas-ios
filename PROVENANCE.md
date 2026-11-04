# Source provenance

## Original project

The application was developed by Oliver Paver for the 2025 BSc Computer Science
project *Advanced Dynamic Road Hazard Detection with Navigation on a Mobile
Platform* at The University of Manchester, supervised by Dr Terrence Morley.

This repository packages the integrated iOS application as a single
source snapshot. The internal project, scheme and Swift module retain the name
`Video_Lane_Test` so that packaging does not require a module rename.

The original lane-processing algorithms, thresholds, Metal kernels and model
bytes for the retained models are preserved. Scoped changes were approved during
repository preparation:

- Camera configuration now uses `defer` to commit the capture-session configuration
  on every exit path, including when no rear camera exists.
- Departure tests use valid look-ahead intersections and assertions matching the
  existing 20-call calibration and five-call departure debounce. The departure
  implementation is unchanged.
- The experimental speed-limit recognition feature, model and UI indicator were
  excluded from the portfolio scope at the author's request. The map's GPS-derived
  current-speed display remains. The excluded experiment is retained with the
  original project outside this repository.

Build settings use neutral example bundle identifiers and no personal development
team. Generated editor state, private profiling exports and redundant project
archives are excluded. The original source and model artifacts are retained separately.

Documentation, model checksums, build instructions and selected historical
demonstration excerpts were added during repository preparation in November 2026.
See [validation](docs/VALIDATION.md) for checks actually performed on this snapshot.

## Attribution boundaries

- The application integrates a pretrained LaneNet network. It does not claim
  authorship of the original LaneNet or BiSeNet V2 architectures.
- The custom application pipeline includes mask processing, Metal clustering,
  cubic fitting and rendering, lane-warning heuristics, camera/video ingestion,
  sign-model integration and navigation.
- The stop-sign model identifies Oliver Paver as its author and contains Create ML
  metadata. Its training-data attribution is recorded separately.
- Model hashes establish artifact identity. They do not establish ownership,
  accuracy, training reproducibility or redistribution permission.

## Historical report and demonstrations

The dissertation and 2025 presentation describe the original development and
experiments. The present technical documentation is checked against the supplied
source and model metadata. Where the report's descriptions differ, the current
documentation follows the implementation. Historical timing, accuracy and coverage
figures have not been adopted as current benchmark results.

The demonstration is labelled as historical footage because its exact build
identity was not recorded with the video. [The media guide](docs/DEMO.md) identifies
the excerpt and crop. Model training data and conversion scripts are not included;
see [model provenance](docs/MODELS.md) and [third-party notices](THIRD_PARTY_NOTICES.md).
