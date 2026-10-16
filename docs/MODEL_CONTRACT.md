# Model contract

What a model pair must look like for DetectX 2-Tier to load it: a **detector** (stage 1,
every frame) and a **classifier** (stage 2, once per detected box). Anything that meets
this contract works without code changes: the app reads input sizes, class counts and
quantization from the model files themselves.

Check a pair with Docker only, no Python setup needed:

```bash
tools/check-model.sh detector-a9.tflite labels.txt --target a9 \
    --classifier classifier-a9.tflite classifier-labels.txt
```

The build runs the same check (`app/extract_model_params.py`), so a pair that fails
here also fails `./build.sh`.

## The detector (`.tflite`)

| | Requirement |
|---|---|
| Architecture | YOLOv8 detector (anchor-free, no objectness). YOLOv5 models do not work. |
| Input | one tensor `[1, H, W, 3]`, **uint8**, RGB. H and W multiples of 32. |
| Outputs | exactly two **uint8** tensors: coordinates `[1, 4, N]` (cx, cy, w, h in input pixels) and class scores `[1, classes, N]` (after the sigmoid, 0-1). |
| Box count | `N = (H/8)(W/8) + (H/16)(W/16) + (H/32)(W/32)`, e.g. 10,710 at 960x544. |
| Quantization | full int8. **ARTPEC-8:** per-tensor weights. **ARTPEC-9:** per-channel weights. One file per chip; they are not interchangeable. |

Why two outputs: Ultralytics' own TFLite export produces one fused `[1, 4+classes, N]`
float tensor. Fused, coordinates (0 to the input width) and scores (0-1) share one int8
scale, and every score quantizes to zero. Separate tensors each get their own scale.
Use an exporter that cuts the graph before the final concat -- the training repository
[acap-model-pipeline](https://github.com/pandosme/acap-model-pipeline) does this.

## Input size

- Prefer a 16:9 shape: the camera image is squeezed to the model input without
  letterboxing, so a square input distorts the scene and wastes pixels.
  Common sizes: 640x352, 960x544, 1120x640, 1280x736.
- Both chip files must use the same input size.
- Larger inputs detect smaller and farther objects but run slower. See the README's
  performance tables before going above 960x544 on ARTPEC-8.

## The classifier (`.tflite`)

| | Requirement |
|---|---|
| Architecture | image classifier (e.g. YOLOv8-cls) |
| Input | one tensor `[1, S, S, 3]`, **uint8**, RGB, square (128x128 in the default model) |
| Output | one tensor `[1, classes]`, **uint8**, class probabilities |
| Quantization | as the detector: per-tensor for ARTPEC-8, per-channel for ARTPEC-9 |

**The crop.** For each detected box the app cuts a square around the box centre, side =
longest box side x `classifierCropMargin` (settings, default 1.25), from the camera's
full-resolution stream, and resizes it to S x S. Out-of-frame parts are black. Train the
classifier on crops cut the same way -- acap-model-pipeline's `crops` step does that --
or set `classifierCropMargin` to your training margin.

**No normalisation layer.** The app passes raw RGB bytes; the classifier's uint8 input
must map 0-255 to its own input range (YOLOv8-cls: scale 1/255, zero point 0).

## Labels (`labels.txt`, `classifier-labels.txt`)

`labels.txt` belongs to the detector, `classifier-labels.txt` to the classifier. The
classifier's labels are the ones events, MQTT and crops use; the detector's score is
kept as `detector_c` metadata. Keep a rejection class (e.g. `no_gesture`) in the
classifier for boxes that are none of the real classes, and use it as the threshold
fallback label.


- One label per line, in the model's class order (line 1 = class 0).
- The number of lines must equal the model's class count.
- Labels are shown in the web UI and used in event names and MQTT topics. Spaces work,
  but short lowercase labels without spaces (`no_gesture`) are easier to use in
  integrations.

## Multi-class models: clamp the class logits

A model with many classes can push the score logits of the classes a box is *not* to
extreme values (seen: -133). After int8 quantization the ARTPEC-9 DLPU then returned
false 100 % scores at random positions while the same file was correct on the CPU.
Clamping the logits to +-16 before the sigmoid (`Hardtanh(-16, 16)` after each class
branch) prevents it without changing any prediction. acap-model-pipeline adds the clamp
automatically for models with more than one class.

## Calibration

Int8 export needs representative images: 200-500 frames from the deploying camera at
the export size, covering the distances you care about and including empty scenes.
Calibration decides accuracy on small objects more than anything else in the export.

## Packaging

The build expects, in `app/model/`:

| File | |
|---|---|
| `model-a8.tflite`, `model-a9.tflite` | detectors |
| `labels.txt` | detector labels |
| `classifier-a8.tflite`, `classifier-a9.tflite` | classifiers |
| `classifier-labels.txt` | classifier labels |

The two chips may use different detector input sizes (the default model uses 960x544 on
ARTPEC-8 and 1280x736 on ARTPEC-9). `tools/install-model.sh` puts the files there from a
two-tier model package (`mymodel-a8-960x544.tflite`, ..., `labels.txt`, and a
`classifier/` folder) and records the source in `app/model/SOURCE.md`.

The web UI's **Model** page and `tools/camera.sh <camera> upload-model` replace the
detector at runtime; the classifier is replaced by building.
