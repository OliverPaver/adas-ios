# Third-party notices

This document identifies external components and the provenance currently established for the project's assets. It does not grant a license to the entire repository or extend an upstream license to unrelated models, images, datasets, or application code.

## LaneNet implementation reference

- Upstream project: [MaybeShewill-CV/lanenet-lane-detection](https://github.com/MaybeShewill-CV/lanenet-lane-detection).
- Upstream copyright notice: **Copyright 2018 Luo Yao**.
- Upstream license: **Apache License 2.0**. The upstream license text, including its copyright notice, is retained in [LICENSES/LaneNet-Apache-2.0.txt](LICENSES/LaneNet-Apache-2.0.txt).
- License reference checked at revision [`fb31c8e4877d08c548af6f93687727a687f8cd9b`](https://github.com/MaybeShewill-CV/lanenet-lane-detection/tree/fb31c8e4877d08c548af6f93687727a687f8cd9b) on 4 November 2026. [Pinned upstream license](https://github.com/MaybeShewill-CV/lanenet-lane-detection/blob/fb31c8e4877d08c548af6f93687727a687f8cd9b/LICENSE).

The project report attributes its LaneNet model to this upstream implementation. On 4 November 2026, Oliver Paver confirmed that he downloaded the maintainer-linked BiSeNet V2/TuSimple pretrained weights named `tusimple_lanenet.ckpt` and personally converted them to Core ML. The retained artifact embeds TensorFlow 1.15.0 and coremltools 8.2 conversion metadata. The exact historical checkpoint hash and conversion script have not been recovered. The revision above pins the licence reference used for this documentation; it is not asserted to be the original conversion's source revision or checkpoint version.

The conversion and iOS inference/postprocessing integration are part of this project. The preserved Core ML artifact has not been changed during repository preparation. The upstream license copy records the implementation's attribution; it is not a repository-wide licence grant for this application or for unrelated assets.

The [upstream README](https://github.com/MaybeShewill-CV/lanenet-lane-detection/blob/fb31c8e4877d08c548af6f93687727a687f8cd9b/README.md#test-model) distributes the maintainer's pretrained weights and attributes training to TuSimple. The maintainer also [identifies the BiSeNet V2 checkpoint filename](https://github.com/MaybeShewill-CV/lanenet-lane-detection/issues/404#issuecomment-645164294). The linked weight archive was inspected on 4 November 2026: it contained four checkpoint files and no separate licence or notice. No conflicting weight-specific restriction was found in the inspected upstream materials.

Distribution of those checkpoints through the Apache-licensed project provides a reasonable basis for interpreting the maintainer's weights as covered by the project licence. That is an inference from the distribution context, not an explicit weights-specific declaration. An absent licence file inside the ZIP does not itself establish missing permission or prohibit redistribution.

[Apache 2.0, sections 1, 2 and 4](https://www.apache.org/licenses/LICENSE-2.0) permit redistribution of licensed works and derivatives in source or object form, subject to their conditions. Once the input weights are covered, conversion to Core ML does not independently require a new permission. Retain the licence and applicable copyright/attribution/NOTICE material, and prominently identify the conversion and any other modifications.

The author's confirmation resolves the download-source question. This repository carries the converted artifact with the upstream Apache 2.0 licence, copyright attribution, and [conversion notice](MODEL_NOTICES.txt), based on the distribution context described above. Exact checkpoint hashes, numerical reconversion and recovery of the original script would improve reproducibility; they are not conditions imposed by Apache 2.0. [Model provenance details](docs/MODELS.md#checkpoint-provenance) distinguish the author's source confirmation from independently verified artifact hashes. An explicit maintainer statement about the external weights would be additional evidence, not a newly discovered requirement; no request has been sent.

## TuSimple source and test fixture

`Video_Lane_TestTests/lane_lines.jpg` is an exact content match for the LaneNet repository's [data/tusimple_test_image/0.jpg](https://github.com/MaybeShewill-CV/lanenet-lane-detection/blob/fb31c8e4877d08c548af6f93687727a687f8cd9b/data/tusimple_test_image/0.jpg). Both are 262,236 bytes with Git blob identifier `a2c31e97a243460e61610d4d1c01a86239c9a385`; the local file's SHA-256 is recorded below. This establishes its immediate source and resolves the previously missing source attribution. Credit the LaneNet repository and TuSimple's lane-detection benchmark when using the fixture.

The official [TuSimple benchmark repository](https://github.com/TuSimple/tusimple-benchmark) supplies an [Apache 2.0 licence](https://github.com/TuSimple/tusimple-benchmark/blob/d1f5ef1b6fff78c92c61864abcc07a9714900360/LICENSE). Its dataset-download discussion supplies the missing scope evidence: a user [asked specifically about the dataset's licence and commercial use](https://github.com/TuSimple/tusimple-benchmark/issues/3#issuecomment-806523250), and contributor `kivinju` [confirmed Apache 2.0 after legal review on 3 June 2021](https://github.com/TuSimple/tusimple-benchmark/issues/3#issuecomment-854030943). This dataset-specific exchange resolves the earlier uncertainty that arose from inspecting only the separate code-licensing discussion.

The fixture is therefore documented as **TuSimple data under Apache 2.0**, obtained through the attributed LaneNet repository. A verbatim copy of TuSimple's licence is included in [LICENSES/TuSimple-Apache-2.0.txt](LICENSES/TuSimple-Apache-2.0.txt). The image bytes are unchanged; the file was renamed from upstream `0.jpg` to `lane_lines.jpg`. The LaneNet source attribution and licence are also retained. No replacement image or further source information from the project author is required for this fixture.

The old benchmark terms link appears under the [competition's prize conditions](https://github.com/TuSimple/tusimple-benchmark/blob/master/doc/lane_detection/readme.md#prizes). Its unavailability is not treated as evidence of additional unknown image-use restrictions. The dataset licence does not, by itself, establish the origin of a separate converted model.

## Create ML stop-sign model and Roboflow data

The stop-sign model embeds Oliver Paver as author, but does not embed a dataset identity or redistribution license. The author has identified the stop-sign dataset below. Related annotation exports support that attribution; no recovered Create ML project or training-run record conclusively links a numbered export to the saved model. The [model documentation](docs/MODELS.md#sign-training-provenance) records the evidence and its limits.

### Stop-sign dataset attribution

- Dataset: [*stopsign Dataset*](https://universe.roboflow.com/stop-sign-ergmn/stopsign-hx5qv-abjnp), by **Stop Sign**, Roboflow Universe, August 2024.
- Project identity: workspace `stop-sign-ergmn`, project `stopsign-hx5qv-abjnp`.
- Displayed licence: [**Creative Commons Attribution 4.0 International (CC BY 4.0)**](https://creativecommons.org/licenses/by/4.0/), verified by browser inspection on 4 November 2026.
- Identified use: stop-sign training data, as confirmed by the project author. The listing has 3,048 images and class `3`, matching the local export total and model class.
- Repository preparation does not modify or include the raw training images. Historical export preprocessing and the exact training run have not been fully recovered; see [model provenance](docs/MODELS.md#sign-training-provenance).

CC BY 4.0 permits sharing and adaptation subject to its terms, including appropriate credit, a licence link and identification of changes. It also prohibits imposing additional restrictions on the licensed material. This attribution identifies the dataset's displayed licence; it does not automatically assign that licence to the trained model binary or the application source, and it does not imply endorsement.

The public [WeWillDoIt version 2 release](https://universe.roboflow.com/wewilldoit/stopsign-hx5qv/dataset/2) is also labelled CC BY 4.0 and matches the local split counts exactly (2,552 / 283 / 213). Its relationship to the author-identified project is not independently established, so it is documented as a provenance lead rather than a confirmed original export.

Roboflow explains that uploaders [choose licensing options for public data](https://discuss.roboflow.com/t/does-roboflow-jointly-own-my-image-data/4245/3). Its [dataset export documentation](https://docs.roboflow.com/datasets/versions/dataset-versions/exporting-data) identifies releases by workspace, project, and version. The stop-sign project and displayed licence are established; the exact export/training linkage still requires records.

Section 5 of the [Roboflow terms](https://roboflow.com/terms), marked 3 May 2024, addresses rehosting downloaded datasets or content and requires the author's permission. That provision concerns the downloaded content; it is not treated here as an automatic license or prohibition for independently trained Core ML model files. Dataset-specific rights and the saved models' provenance must be established before assigning distribution terms. Raw training images are not part of this repository.

## Research references

The upstream LaneNet implementation cites Davy Neven and colleagues, [*Towards End-to-End Lane Detection: an Instance Segmentation Approach*](https://arxiv.org/abs/1802.05591). The implementation also documents a BiSeNet V2 backbone variant. Research citations acknowledge the methods; they do not replace software, model, or dataset license notices.

## Apple platform frameworks

The app uses Apple SDK frameworks, including SwiftUI, UIKit, AVFoundation, PhotosUI, Core ML, Vision, Metal/MetalKit, Accelerate, MapKit, and Core Location. They are supplied by the Apple development environment and operating system, rather than vendored in this repository. Their use is governed by the applicable Apple SDK and service terms. Create ML and coremltools appear in the model creation/conversion provenance; they are not additional packages that must be installed to build the existing iOS app.

## Asset status

| Asset | Established provenance | Remaining distribution information |
| --- | --- | --- |
| `LaneNet.mlpackage` | Author confirms conversion of the maintainer-linked BiSeNet V2/TuSimple checkpoint; Apache 2.0 distribution basis documented | Source check complete; retain the included licence, copyright and conversion notice. Historical checkpoint hash/script remain reproducibility gaps. |
| `Stop_sign_test3.mlmodel` | Embedded author Oliver Paver; Create ML metadata; author-identified Stop Sign dataset with verified CC BY 4.0 listing | Select an explicit licence for the author's model and retain dataset attribution; exact training-run linkage remains a reproducibility gap |
| `Video_Lane_TestTests/lane_lines.jpg` | Exact LaneNet/TuSimple image match; dataset-specific Apache 2.0 confirmation; SHA-256 `79ec48c6cf63c7d702dcab408091d20ad110f59b1011b1d700e3cc30d9cdbf1a` | Resolved: retain the included licence copies and source/rename attribution above |

The LaneNet source/attribution review and the test fixture's licence record are complete on the documented evidence. No replacement of either artifact is required by this review. The author's licence choice for original work remains separate and has not been made. Moving an asset to a release download or Git LFS does not change its licensing requirements. The raw training datasets are not included.

No repository-wide open-source licence has been selected. The LaneNet licence applies to the identified upstream work; it does not select a licence for the original application code or author-trained stop-sign model. Each third-party asset retains the terms stated above.

