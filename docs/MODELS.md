# Models

The app uses two original Core ML model artifacts: LaneNet and a stop-sign detector. They are preserved unchanged so that the documented input contracts and the Swift integration refer to the same files. [MODEL_MANIFEST.json](../MODEL_MANIFEST.json) records their byte sizes and SHA-256 hashes; the manifest establishes file identity, not redistribution rights.

Run the integrity check from the repository root:

```sh
python3 scripts/verify_models.py
```

Xcode compiles these assets and generates the `LaneNet` and `Stop_sign_test3` Swift model interfaces. Keep the complete `LaneNet.mlpackage`, including its `Manifest.json`, model protobuf, and `weights/weight.bin`. The generated Swift interfaces and compiled `.mlmodelc` directories are build products.

## LaneNet

| Property | Preserved artifact |
| --- | --- |
| Location | `Video_Lane_Test/LaneNet.mlpackage` |
| Total package size | 4,877,060 bytes |
| Model representation | ML Program; Core ML specification version 6 |
| Input | `lanenet_input_tensor`: Float32 `[1, 256, 512, 3]` |
| Binary output | `lanenet_final_binary_output`: Float32 `[256, 512]` |
| Instance embedding output | `lanenet_final_pixel_embedding_output`: Float32 `[256, 512, 4]` |
| Embedded conversion source | `tensorflow==1.15.0` |
| Embedded converter version | `coremltools 8.2` |

`LaneDetector.swift` crops the bottom 60% of a frame, resizes it to 512 pixels wide by 256 pixels high, and writes RGB values in NHWC order. Each channel is normalized using `(value - 127.5) / 127.5`. Resizing does not preserve the crop's aspect ratio. These preprocessing choices belong to the original implementation.

The binary output is thresholded at 0.5. Morphological cleanup and small-component filtering produce a mask; the four-dimensional embedding vectors at retained pixels feed the app's clustering stage. Ego-lane selection and cubic fitting happen in the app after model inference. The model does not directly output lane-departure or collision-warning decisions.

The project report identifies [MaybeShewill-CV/lanenet-lane-detection](https://github.com/MaybeShewill-CV/lanenet-lane-detection) as the upstream implementation and describes its BiSeNet V2 backbone. The retained model graph corroborates this architecture: its operation identifiers include `bisenetv2_frontend_detail_branch`, `bisenetv2_frontend_semantic_branch`, and `bisenetv2_backend_binary_seg`. The four-dimensional output contract above is verified from the artifact.

### Checkpoint provenance

The author has confirmed the checkpoint's source and name. The following independent evidence corroborates the implementation family. Exact numerical matching to the historical download remains a reproducibility gap, separate from the licensing assessment.

| Evidence | What it establishes |
| --- | --- |
| [Upstream configuration](https://github.com/MaybeShewill-CV/lanenet-lane-detection/blob/fb31c8e4877d08c548af6f93687727a687f8cd9b/config/tusimple_lanenet.yaml) | BiSeNet V2 frontend, four embedding features, and 512 × 256 evaluation dimensions agree with the retained model. |
| [Upstream freezing script](https://github.com/MaybeShewill-CV/lanenet-lane-detection/blob/fb31c8e4877d08c548af6f93687727a687f8cd9b/mnn_project/freeze_lanenet_model.py) | Its input and two output tensors correspond to the Core ML interface, with TensorFlow path separators represented as underscores after conversion. The script accepts a checkpoint path; matching the graph does not identify the weights supplied to it. |
| [Maintainer's checkpoint identification](https://github.com/MaybeShewill-CV/lanenet-lane-detection/issues/404#issuecomment-645164294) | The upstream BiSeNet V2 checkpoint is named `tusimple_lanenet.ckpt`. |
| [Upstream-linked weight folder](https://www.dropbox.com/sh/0b6r0ljqi76kyg9/AADedYWO3bnx4PhK1BmbJkJKa?dl=0) | On 4 November 2026, the folder was titled `BiseNetV2_LaneNet_Tusimple_Model_Weights`. Its ZIP contained `checkpoint` and the `.meta`, `.index`, and `.data-00000-of-00001` files for `tusimple_lanenet.ckpt`; no README, license, or notice file was included. |

The inspected upstream checkpoint components have the following identities. They are provenance leads, not substitutes for [the app's artifact hashes](../MODEL_MANIFEST.json):

| Upstream file | Bytes | SHA-256 |
| --- | ---: | --- |
| `tusimple_lanenet.ckpt.index` | 36,719 | `1a7f4560331cb87288eec28d4a0acaca7c773171afce0fcc1d52aa1924191f8a` |
| `tusimple_lanenet.ckpt.data-00000-of-00001` | 27,938,248 | `ddda5ddd77b1c5a7a1b42772ed2596e5db1a8ef09f54e6667b9216d512c55584` |

On 4 November 2026, Oliver Paver confirmed that he used the BiSeNet V2/TuSimple pretrained weights named `tusimple_lanenet.ckpt` from the maintainer-linked download in MaybeShewill-CV's repository and personally converted them from TensorFlow to Core ML. This is author-confirmed provenance, not an independent numerical comparison with the original downloaded checkpoint. The format change and upstream attribution are recorded in [MODEL_NOTICES.txt](../MODEL_NOTICES.txt).

No original frozen graph, checkpoint, or Core ML conversion script was located in the accessible project materials. The available local LaneNet copies have identical model and weight hashes. The upstream checkpoint has not been reconverted or numerically matched to the bundled Core ML weights. Its filename, architecture, and matching interface therefore do not independently verify this artifact's parameters against the original download. The embedded TensorFlow and coremltools versions identify conversion tools, not the exact historical checkpoint bytes.

The upstream licence and distribution context are assessed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md#lanenet-implementation-reference). Apache 2.0 permits conversion and redistribution of covered work subject to its conditions; it does not require recovering the original script or proving a numerical checkpoint match. The author has supplied the requested source confirmation, and the licence and conversion notices are included. The TuSimple dataset's Apache 2.0 scope is supported by a dataset-specific maintainer statement, as recorded in the notices.

## Stop-sign detector

| Property | Preserved artifact |
| --- | --- |
| File in `Video_Lane_Test/` | `Stop_sign_test3.mlmodel` |
| Size | 31,750,985 bytes |
| Model input | RGB image, 416 × 416 |
| Input name | `imagePath` |
| Class label | `3` |
| Outputs | `confidence`, `coordinates` |
| Embedded author | Oliver Paver |
| Embedded Create ML app version | 6.0 Beta |
| Embedded Create ML version | 14.5.0 |
| Embedded iteration count | 16,000 |

The artifact contains a neural-network detector followed by non-maximum suppression. The model interface includes optional `iouThreshold` and `confidenceThreshold` inputs, with embedded defaults of approximately 0.45 and 0.25. The app adds a separate label-confidence filter of 0.5 in `StopSignDetector`. It invokes the model through Vision without explicitly setting `imageCropAndScaleOption`.

`StopSignDetector` returns whether label `3` passes its threshold.

The metadata records how the saved artifact describes itself. The iteration count is not an independently reproduced training log or an accuracy measurement.

### Sign-training provenance

The project author identified [the Stop Sign workspace's `stopsign` dataset](https://universe.roboflow.com/stop-sign-ergmn/stopsign-hx5qv-abjnp) as the stop-sign training source. Browser inspection on 4 November 2026 verified its public listing: **3,048 images, class `3`, and CC BY 4.0**. The page's citation credits **Stop Sign**, August 2024. It currently lists zero published dataset versions and zero models, so a numbered export cannot be recovered from that project listing.

Local Create ML annotation exports contain **2,552 training, 283 validation, and 213 test records**, all using label `3`, with 3,048 distinct filenames across the splits. The total agrees with the author-identified dataset and project report. No recovered Create ML project or training-run record ties a particular export and its settings conclusively to `Stop_sign_test3.mlmodel`.

A related public release, [WeWillDoIt's `stopsign` version 2](https://universe.roboflow.com/wewilldoit/stopsign-hx5qv/dataset/2), was generated on 8 April 2024 and lists exactly the same split counts. It also lists CC BY 4.0, automatic orientation, resizing by stretching to 640 × 640, and no augmentations. This is a strong provenance lead, not proof of a fork relationship or the exact downloaded release: individual exported files have not been matched. Its separate Roboflow-hosted model and evaluation results are not the application's Create ML model or its results.

Remaining provenance includes the stop-sign export/version and training-run link. Roboflow's [export documentation](https://docs.roboflow.com/datasets/versions/dataset-versions/exporting-data) describes version-specific exports, including CreateML format. Matching that format and a class label is insufficient to identify an exact dataset release. The confirmed stop-sign dataset licence and attribution are recorded in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md#create-ml-stop-sign-model-and-roboflow-data).

## Reproduction and distribution status

The model files support reproduction of the existing inference integration, subject to the documented build and device requirements. This repository does not currently reproduce model training or TensorFlow-to-Core-ML conversion: training projects, versioned training configurations, the split actually used by each training run, original checkpoint files, and conversion commands are unavailable here.

The author-identified stop-sign dataset is attributed with its displayed CC BY 4.0 licence. LaneNet's author-confirmed upstream source and Apache 2.0 distribution basis are documented separately. No raw training datasets are included in this repository. The [asset status table](../THIRD_PARTY_NOTICES.md#asset-status) distinguishes completed attribution from the author's outstanding licence choice for original work; a dataset licence is not applied automatically to every model or to the application source.

There is no verified download URL for these exact converted artifacts. Replacing the files with a similarly named upstream model would not reproduce this application automatically: the generated interface, tensors, preprocessing, label mapping, and hash manifest must all match. A future downloadable model release should provide these exact artifacts, their provenance and applicable notices, and checksums. Until then, the retained local artifacts are the reference for validation.

