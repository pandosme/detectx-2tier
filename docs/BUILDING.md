# Building DetectX 2-Tier with your own models

You need Docker (or Podman) and a trained model pair that meets the
[model contract](MODEL_CONTRACT.md): per chip a detector and a classifier `.tflite`,
plus `labels.txt` and `classifier-labels.txt`.
No Axis SDK installation is needed; the build runs in the SDK's Docker image.

## 1. Install the model

From a two-tier model package (the folder acap-model-pipeline produces):

```bash
tools/install-model.sh ~/datasets/mymodel/models --size 960x544
```

or from individual files:

```bash
tools/install-model.sh --a8 det-a8.tflite --a9 det-a9.tflite --labels labels.txt \
    --classifier-a8 cls-a8.tflite --classifier-a9 cls-a9.tflite --classifier-labels classifier-labels.txt
```

Each chip's pair is checked first (`tools/check-model.sh`, about 2 seconds after the
first run). The files are copied to `app/model/` (`model-<chip>.tflite`,
`classifier-<chip>.tflite`, `labels.txt`, `classifier-labels.txt`) and
`app/model/SOURCE.md` records where they came from. Review the classifier settings in
`app/settings/settings.json` too: `classifierCropMargin` (must match training),
`classifierConfidence` and `classifierFallbackLabel`, and the labels unticked by default
(`ignore`).
Commit `app/model/` if this is your own fork: it is the model your package ships.

## 2. Build

```bash
./build.sh                 # ARTPEC-8 and ARTPEC-9 packages
./build.sh --target a9     # one chip only
./build.sh --clean         # rebuild the Docker layers without cache
CRUNTIME=podman ./build.sh
```

Packages are written to the repository root: `DetectX_2-Tier_<version>_artpec8.eap` and
`DetectX_2-Tier_<version>_artpec9.eap`. The version comes from `app/manifest.json`. To ship
your own application, change `appName`, `friendlyName` and `version` there.

## 3. Install and run

In the camera's web interface: **Apps → Add app**, choose the package for the camera's
chip, then start it. Axis OS 12 and later only run unsigned apps after **Allow unsigned
apps** is enabled (or with the Developer Mode app on Axis OS 13). ARTPEC-9 needs Axis OS
13 or later.

Or from the command line:

```bash
export AXIS_USER=<user> AXIS_PASS=<password>
tools/camera.sh <camera> install DetectX_2-Tier_5_1_0_artpec9.eap
tools/camera.sh <camera> status          # state, FPS and inference time
tools/camera.sh <camera> log 100         # the app's lines from the system log
tools/camera.sh <camera> restart
```

The first start compiles the model for the DLPU; that takes 30-90 seconds (longer for
large inputs on ARTPEC-8).

## Trying a detector without building

To compare detectors or input sizes on a camera, upload them to the installed app (the
classifier stays the one in the package):

```bash
tools/camera.sh <camera> upload-model my-a9.tflite labels.txt
```

The app stores it, restarts and reports its FPS. `tools/benchmark_resolutions.sh` does
this for a folder of models and prints a speed table; `tools/benchmark_larod.sh` times
raw DLPU inference over SSH.

## Tools

| Tool | |
|---|---|
| `tools/install-model.sh` | model package or files -> `app/model/`, with checks |
| `tools/check-model.sh` | check a `.tflite` + labels against the model contract (Docker) |
| `tools/camera.sh` | install, start/stop/restart, status, log, upload-model (VAPIX) |
| `tools/benchmark_resolutions.sh` | upload each model in a folder, measure FPS on the camera |
| `tools/benchmark_larod.sh` | raw DLPU inference time per model (SSH, larod-client) |

## Troubleshooting

| Symptom | Cause |
|---|---|
| `per-axis quantized tensors; ARTPEC-8 requires per-tensor` | an ARTPEC-9 export in the ARTPEC-8 slot |
| `no per-axis quantized tensors` | an ARTPEC-8 export in the ARTPEC-9 slot |
| `has N classes but labels.txt has M labels` | labels file does not belong to the model |
| `expected 2 split YOLOv8 outputs` | a stock Ultralytics export; re-export with a split exporter |
| High-confidence nonsense on ARTPEC-9 only | Axis OS older than 13, or a multi-class model without the logit clamp |
| Model loads but runs ~10x slower | an operation fell back to the CPU; check the log for "not supported" |
