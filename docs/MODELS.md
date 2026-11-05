# Models

The app bundles two unchanged Core ML artifacts. [MODEL_MANIFEST.json](../MODEL_MANIFEST.json) records sizes and SHA-256 hashes. Verify them from the repository root:

```sh
python3 scripts/verify_models.py
```

Xcode generates the `LaneNet` and `Stop_sign_test3` Swift interfaces. Keep the complete LaneNet package, including its manifest, model and weights; generated interfaces and compiled `.mlmodelc` directories are build products.

## LaneNet

Artifact: `Video_Lane_Test/LaneNet.mlpackage`, an ML Program using Core ML specification version 6.

| Contract | Float32 tensor |
| --- | --- |
| Input: `lanenet_input_tensor` | `[1, 256, 512, 3]` |
| Binary output: `lanenet_final_binary_output` | `[256, 512]` |
| Embeddings: `lanenet_final_pixel_embedding_output` | `[256, 512, 4]` |

`LaneDetector` crops the bottom 60% of the frame, stretches it to 512 × 256, and writes RGB channels in NHWC order, normalized as `(value - 127.5) / 127.5`. It thresholds the binary output at `> 0.5`, cleans the mask, and clusters retained pixels using their four-dimensional embeddings. Lane selection, cubic fitting and warning decisions happen in the app after inference.

### Checkpoint provenance

Oliver Paver confirms personally converting the maintainer-linked BiSeNet V2/TuSimple `tusimple_lanenet.ckpt` from [MaybeShewill-CV's LaneNet](https://github.com/MaybeShewill-CV/lanenet-lane-detection). Embedded metadata records TensorFlow 1.15.0 and coremltools 8.2.

The original checkpoint, frozen graph, historical checkpoint hash and conversion script were not recovered. The source is author-confirmed; numerical equivalence to the historical checkpoint has not been independently verified. These are reproduction gaps, not additional licence conditions.

The Apache 2.0 distribution basis and scope interpretation are explained in [third-party notices](../THIRD_PARTY_NOTICES.md#lanenet-implementation-reference); [MODEL_NOTICES.txt](../MODEL_NOTICES.txt) records the conversion and attribution.

## Stop-sign detector

Artifact: `Video_Lane_Test/Stop_sign_test3.mlmodel`.

| Contract | Value |
| --- | --- |
| Input: `imagePath` | RGB image, 416 × 416 |
| Outputs | `confidence`, `coordinates` |
| Stop-sign class | `3` |

The neural-network detector includes non-maximum suppression. Optional `iouThreshold` and `confidenceThreshold` inputs default to approximately 0.45 and 0.25. The app uses Vision without explicitly setting `imageCropAndScaleOption`, then returns whether label `3` has confidence `>= 0.5`.

Metadata identifies Oliver Paver, Create ML app 6.0 Beta, Create ML 14.5.0 and 16,000 iterations. This is saved metadata, not a reproduced training log or accuracy result.

### Sign-training provenance

The author identifies [Stop Sign's Roboflow dataset](https://universe.roboflow.com/stop-sign-ergmn/stopsign-hx5qv-abjnp): 3,048 images, class `3`, CC BY 4.0, credited to Stop Sign, August 2024. Local annotation exports contain 2,552 training, 283 validation and 213 test records.

The exact export/version, Create ML project and training-run settings linking those exports to this model were not recovered. Dataset attribution and licence scope are recorded in [third-party notices](../THIRD_PARTY_NOTICES.md#create-ml-stop-sign-model-and-roboflow-data).

The bundled artifacts support the existing inference integration; this repository does not reproduce training or conversion. Raw training datasets are excluded. A similarly named replacement model is not interchangeable without checking its interface, preprocessing and labels.

