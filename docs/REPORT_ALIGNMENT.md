# Design and report notes

The project accompanies Oliver Paver's 2025 BSc dissertation, *Advanced Dynamic
Road Hazard Detection with Navigation on a Mobile Platform*, at The University of
Manchester, supervised by Dr Terrence Morley. It investigates combining navigation
and camera-based road perception on an ordinary iPhone.

The main engineering work turns LaneNet's mask and pixel embeddings into lane
instances, fitted curves and warning state, while coordinating capture, mapping
and display. The [README](../README.md#how-the-system-works) explains that pipeline;
[architecture](ARCHITECTURE.md) maps it to the source.

| Dissertation reference | Topic |
| --- | --- |
| §§1.1–1.2, pp. 7–8 | Objectives and contributions |
| §4, pp. 17–18; §5.2, pp. 22–25 | Navigation and stop-sign recognition |
| §§6.2, 6.5.3, 6.5.5, pp. 28–39 | Lane processing, Metal clustering and batched fitting |
| §§6.8–6.9, pp. 47–49 | Departure and corridor monitoring |

The report is not bundled. Page numbers refer to its supplied final version.
Documentation follows the retained code where descriptions differ: embeddings
have four components, clustering uses fixed propagation passes, and warnings use
image-space geometry. Historical performance observations are not presented as
reproduced benchmarks. See [validation](VALIDATION.md) for current evidence and
[limitations](LIMITATIONS.md) for unresolved behavior.
