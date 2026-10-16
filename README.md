# DetectX 2-Tier

Run a **two-stage YOLOv8 model** on Axis cameras with ARTPEC-8 or ARTPEC-9: stage 1
finds objects in every frame, stage 2 classifies each object from a full-resolution
crop. Results go out over MQTT, ONVIF events, HTTP, crop export and SD training capture,
with the full DetectX feature set.

The package ships **HandGesture's model** as a working default: a hand detector and a
15-gesture classifier trained on the [HaGRID](https://github.com/hukenovs/hagrid) dataset
plus real camera footage. DetectX 2-Tier is meant as a **base for your own two-tier
models**: it reads input sizes, class counts and quantization from the model files, so a
pair you train and export with
[acap-model-pipeline](https://github.com/pandosme/acap-model-pipeline) needs no code
changes.

The package identity is `detectx`, the same as DetectX: it replaces DetectX on a camera
rather than running next to it.

## Acknowledgements

Thanks to [Pavel Kotyza](https://github.com/kotyzap) for his work enabling
YOLOv8 models on Axis cameras through
[YOLOv8-on-AXIS-ACAP](https://github.com/kotyzap/YOLOv8-on-AXIS-ACAP).

> **ARTPEC-9 requires Axis OS 13 or later.** Earlier firmware miscomputes YOLOv8 on the
> A9 DLPU -- the model loads and runs at full speed but returns high-confidence garbage,
> while the same package is correct on ARTPEC-8.

### Choose your path

| You want to... | Do this | You need |
|---|---|---|
| Try two-tier detection with the hand-gesture model | Install a package from [Releases](https://github.com/pandosme/detectx-2tier/releases) | an Axis camera |
| Ship a package with your own model pair | `tools/install-model.sh` then `./build.sh` -- see [docs/BUILDING.md](docs/BUILDING.md) | Docker |
| Train your own two-tier model | [Train your own two-tier model](#train-your-own-two-tier-model) below, with acap-model-pipeline | a GPU is recommended |
| Run a single-stage model | Use [DetectX](https://github.com/pandosme/DetectX) | -- |
| Use hand gestures as a finished product | Use [HandGesture](https://github.com/pandosme/HandGesture) (selectable detection range, gesture events, user documentation) | an Axis camera |

This repository holds the application only. Training, datasets and export live in
acap-model-pipeline; the two meet at the [model contract](docs/MODEL_CONTRACT.md).

## One tier or two?

**DetectX (one tier)** runs one detector whose classes are the answer. **DetectX 2-Tier**
runs a detector that only has to *find* the object, then a classifier that decides *what
it is* from a crop of the camera's full-resolution image.

| Use DetectX (one tier) when... | Use DetectX 2-Tier when... |
|---|---|
| the classes look different at the size the detector sees them (person, car, bicycle, bird, a dumped object) | the classes differ in small details of the object (hand gestures, vehicle make, PPE worn or not, species) |
| objects are large in the image, or near | objects are small or far, but the detail is still visible at full resolution |
| many objects per frame (the classifier runs once per object) | few objects per frame |
| you want one model to train and maintain | you can train two models and keep their data apart |

The difference is pixels. A detector at 1120x640 sees a 4K scene at about a quarter of
its resolution; a hand 40 px wide in 4K is 10-12 px at the detector, too few to read a
gesture. The two-tier classifier reads the same hand from the 4K image. Measured on 435
held-out real hands from our cameras (share with the right gesture, same detector input
1120x640):

| | full image | View Area 1446 px wide |
|---|---|---|
| One tier: 15-gesture YOLOv8n trained on HaGRID + camera data | 0.66 | 0.85 |
| **Two tier: hand detector + gesture classifier (this default model)** | **0.85** | **0.92** |

The gap is largest for small hands (36-60 px in 4K: 0.61 vs 0.87). A View Area narrows
it because it gives every object more pixels -- see *Range* below.

The price of two tiers: two models to train, and the classifier runs once per detected
object (13-20 ms each on ARTPEC-8), so many objects lower the frame rate.

## The default model: hand gestures

| | ARTPEC-8 | ARTPEC-9 |
|---|---|---|
| Stage 1: hand detector (YOLOv8n, 1 class `hand`) | Hands v4 at **960x544** | Hands v5 at **1280x736** |
| Stage 2: gesture classifier (YOLOv8s-cls) | gesture15, 128x128 | gesture15, 128x128 |
| Frame rate, no hand / one hand | ~10 / 8.6 FPS | ~8 / 7 FPS |

Gestures (classifier labels): call, dislike, fist, four, like, middle_finger, mute,
no_gesture, ok, one, palm, peace, rock, stop, three.

- **Hand detector:** trained on ~1,900 verified frames from five Axis cameras (indoor and
  outdoor, day and night), HaGRID images with every hand labelled, and person-free frames.
  Hands v5 is a fine-tune of v4 at the larger input; it finds 93 % of the test hands
  against 88 % for v4, most of the gain on hands 32-64 px wide in a 4K image.
- **Gesture classifier:** HaGRID gesture crops (6,000 per class) plus ~1,900 verified real
  hands cut the way the app cuts them, with shifted and resized boxes to mimic the
  detector's box errors, and false hand detections (elbows, plants) as `no_gesture`.
  93-96 % right on held-out real hands; weakest are `fist` (read as `one`) and `three`
  (read as `peace`).
- **Default settings** for this model: detector confidence 40, NMS 0.2, classifier
  threshold 60 % with fallback `no_gesture`, and `no_gesture` unticked so idle hands do not
  fire events. If you install your own models, review these in
  `app/settings/settings.json`.
- Trained on one person and two cameras; expect lower accuracy for other people and
  viewpoints. [HandGesture](https://github.com/pandosme/HandGesture) documents range and
  performance for the same models in detail.

## Quick Start

### Downloading a Pre-Compiled Package

Two packages are published per release, one per chipset -- they are **not**
interchangeable:

| Package | Chip |
|---|---|
| `DetectX_2-Tier_<version>_artpec8.eap` | ARTPEC-8 |
| `DetectX_2-Tier_<version>_artpec9.eap` | ARTPEC-9 |

ARTPEC-8 models are quantized per-tensor, ARTPEC-9 per-channel; the wrong package gives
wrong detections.

> **Axis OS 13 development installs:** To run an unsigned ACAP, first install the
> [Dev-Mode ACAP](https://www.axis.com/es-es/for-developers/news/acap-developer-mode).
> Downloading it requires signing in with a MyAxis account.

### Building the Application

```bash
./build.sh                 # builds both ARTPEC-8 and ARTPEC-9 packages
./build.sh --target a8     # one chip only
```

To build with your own model pair, install it first:

```bash
tools/install-model.sh <two-tier-model-package> --size 960x544
./build.sh
```

The installer checks each chip's detector and classifier against the
[model contract](docs/MODEL_CONTRACT.md) and copies them to `app/model/`. See
[docs/BUILDING.md](docs/BUILDING.md) for details and the command-line camera tools
(`tools/camera.sh`: install, status, log, restart).

## Train your own two-tier model

[acap-model-pipeline](https://github.com/pandosme/acap-model-pipeline) trains and exports
both stages and writes a model package this app installs. You need:

1. **A detector dataset** in YOLO format with **one broad class** (e.g. `hand`, `vehicle`,
   `person`): every instance labelled, plus frames without the object.
2. **Class labels for the classifier**: either per-box labels in the same dataset (the
   pipeline crops them) or a folder of crops per class. Include a **rejection class**
   (e.g. `no_gesture`, `other`) for boxes that are none of the real classes.
3. **Calibration frames** from the camera you deploy on, at the export size.

A two-tier config (`config/mymodel.yaml` in acap-model-pipeline):

```yaml
name: mymodel
models_dir: ~/datasets/mymodel/models      # the model package
acap: ~/acap/detectx-2tier                 # where `install` puts it
crops:                                     # stage-2 dataset, cut like the app cuts
  reader: yolo_txt
  source_images: ~/datasets/mymodel/images
  source_annotations: ~/datasets/mymodel/labels
  out: ~/datasets/mymodel-crops
  size: 128
  margin: 1.25                             # = classifierCropMargin in settings.json
  classes: [class_a, class_b, other]       # keep the rejection class
detector:
  base_weights: yolov8n.pt
  data: ~/datasets/mymodel-detector/data.yaml    # one class
  calib: ~/datasets/mymodel/calib
  imgsz: 960
  export_ladder: [960x544, 1280x736]
classifier:
  base_weights: yolov8s-cls.pt
  calib: ~/datasets/mymodel-crops/val
  imgsz: 128
  hyp: {flipud: 0.0}
```

```bash
tools/get_base_weights.sh n s                          # COCO starting weights
python pipeline.py all -c config/mymodel.yaml          # crops -> train both -> export both
python pipeline.py install -c config/mymodel.yaml --resolution 960x544
cd ~/acap/detectx-2tier && ./build.sh
```

`python pipeline.py <dataset-folder>` runs the same steps as a guided, resumable workflow.

**The worked example is the default model.** The gesture crops were built from HaGRID's
annotations (the pipeline's `hagrid_json` reader, `config/hagrid.yaml`), the hand detector
from HaGRID plus camera frames (`config/hands-960.yaml`, `config/hands-1280.yaml`), and the
classifier from the HaGRID crops plus verified camera crops (`config/handgesture2.yaml`).

## Best practices

What made the difference while building the default model, roughly in order of impact:

**Data**
- **Real camera data beats more internet data.** HaGRID alone gave a detector that missed
  distant hands and a classifier that confused gestures at camera sizes. A few thousand
  verified frames and crops from the deploying cameras fixed most of it.
- **Capture with the app itself.** Run DetectX with a first detector and export crops over
  MQTT at full camera resolution, with a generous border; review them in a labelling tool.
  Auto-label with your previous model and only verify.
- **Label every instance**, including idle or "background" ones (a relaxed hand is
  `no_gesture`, not unlabelled). An unlabelled object teaches the detector to ignore it.
- **Add empty frames**, day and night, from every camera -- including look-alikes (a tarp,
  fence slats, a lamp's glare). They are the cheapest way to remove false detections.
- **Hold out by time, not by image.** Frames seconds apart are near-duplicates; split in
  10-second blocks (or whole sessions) so the test set measures something.

**Detector**
- **Train at the deployment input size.** Our hand detector trained at 1920 and run at 960
  found 83 % of hands; trained at 960 it found 89 %. The detector learns object sizes in
  pixels.
- **Use 16:9 inputs** (960x544, 1120x640, 1280x736); a square input wastes a third of the
  pixels on a 16:9 camera.
- **Range comes from pixels, not model size.** Raise the input size or use a **View Area**
  before using a bigger model. A View Area half the sensor width doubles every object's
  pixels at the same frame rate.
- **Multi-class detectors need a logit clamp** for ARTPEC-9; the pipeline adds it.

**Classifier**
- **Crop exactly like the app**: square, longest box side x 1.25, from the full-resolution
  image. Then add shifted and resized copies of each real crop so the classifier tolerates
  the detector's int8 box errors (box coordinates step ~15 px on a 4K image).
- **Train on small crops too**: degrade a share of the training crops to 16-96 px first.
- **Keep a rejection class** and feed it the detector's false positives.
- **Turn vertical flip off** for orientation-sensitive classes (like vs dislike).

**Export and deployment**
- **Calibrate on frames from the deploying camera at the exact export size**, 300 frames,
  with objects at all distances and some empty scenes. A calibration set without the
  objects skews the int8 ranges.
- **Test on the camera.** The ARTPEC-9 DLPU can differ from a PC int8 run; use the app's
  CPU mode (`chip` setting `cpu-tflite`) to tell a model problem from a DLPU problem.
- **Budget ~5 FPS** for reliable events: the Accuracy vote looks at 500 ms of frames.
  On ARTPEC-8, the camera's own object analytics take 30-40 % of the frame rate at larger
  inputs.
- **Use the classifier threshold** (e.g. 60 % with fallback to the rejection class) and
  untick the rejection class, so uncertain objects never fire events.

***

## Application Overview

DetectX provides real-time detection and state data from network cameras directly to your systems. **Intended for system integrators**, all outputs are designed for machine-to-machine (M2M) workflows, with flexible configuration from a built-in web UI and standards-based output via MQTT, ONVIF, or HTTP.

Typical use cases include:
- Vehicle and person detection in perimeter security
- Counting and presence analytics
- Intelligence enrichment for video management systems (VMS) or IoT platforms

***

## Menu & Feature Walkthrough

Each menu item below describes both *user options* and *integration outputs*, matched to the associated interface screenshot for easy visual orientation.

***

### 1. Detections

Allows you to see object detections overlayed on the video, and to adjust detection parameters.

<img src="pictures/Detections.jpeg" alt="Detections Page" width="500"/>

- **Adjust Confidence Threshold:**  
  Set the minimum confidence (0–100) for labeling a detection as valid.
- **Set Area of Interest (AOI):**  
  Draw a **polygon** to receive detections only from the area inside the polygon. Click to add vertices; drag vertices to reshape.
- **Add Exclude Zones:**  
  Draw one or more **exclude polygons** to suppress detections in specific areas (e.g. tree, reflection, road sign). Multiple zones are supported.
- **Configure Minimum Object Size:**  
  Exclude detections smaller than the specified pixel area.

**Visualization Notes:**
- The overlay updates approximately two times per second (“best effort”). The bounding boxes may lag or not exactly match all detections due to UI and network constraints.
- Use this page for *quick confirmation* that detection is working and properly tuned.

***

### 2. MQTT

Here you configure the gateway between the camera and your backend system.

<img src="pictures/MQTT.jpg" alt="MQTT Page" width="500"/>

- **Broker Address and Port:**  
  Specify the IP or hostname for your MQTT broker and port (default: 1883).
- **Authentication:**  
  Optional username and password if security is enforced.
- **Pre-topic:**  
  The prefix added to all MQTT topics (e.g., `detectx/detection/...`). Change if routing multiple cameras.
- **Additional Metadata:**  
  *Name* and *Location* properties help you distinguish events in multi-camera setups.

**Connection Status** is displayed, along with currently active parameters for fast troubleshooting.

***

### 3. Events/Labels

This section allows you to tailor detection and event signaling to your application:

<img src="pictures/Evenst_Labels.jpg" alt="Detection Export Page" width="500"/>

- **Selectable Labels:**  
  Check or uncheck which object types (labels) are actively processed, reducing false positives or narrowing the scope (e.g., only cars and persons).
- **Event State Settings:**  
  - *Prioritize*: Opt for accuracy (suppresses false triggers) or responsiveness.
  - *Minimum Event State Duration*: Avoid chattering by forcing a minimum active/inactive state period for each label.
- **SD Card Training Capture:**  
  When enabled, full-frame JPEG images and matching YOLO-format label files are saved to the SD card whenever a detection event is active. Images are captured at a configurable interval (1–60 s); the first image is captured immediately on the event going active. A **Download Archive** button packages all captured images and labels into a zip file ready for import into your training pipeline. A **Clear All** button removes all stored files. Capture stops automatically at 2 000 images to protect SD card space.

**Note:**  
Each label produces an independent event state. Tuning event parameters is crucial for noisy or high-traffic scenes.

***

### 4. Detection Export

When downstream systems require not only detection data but *cropped images* for each detection:

<img src="pictures/Detection-Export.jpg" alt="Detection Export Page" width="500"/>

- **Enable/Disable Detection Cropping**
- **Set Border Adjustment:**  
  Expand or shrink the crop region around detected objects (e.g., add 25px margin). Presets available for common use cases.
- **Output Methods:**  
  - **MQTT:** Sends cropped images as base64 payloads.
  - **HTTP POST:** Posts the payload to a configurable endpoint.
- **Throttle Output:**  
  Limit image frequency to reduce load or network traffic.

#### View the Latest Crops
<img src="pictures/crops.jpg" alt="Crops Gallery" width="600"/>
- Opens a gallery of up to 10 most recent image crops, labeled by type and confidence.
- Essential for quality assurance—check that crops are readable, in correct locations, and correspond to real detections.

***

### 5. About

<img src="pictures/About.jpg" alt="About Page" width="480"/>

A dashboard combining:
- **Model Status:** Input size, inference time, DLPU backend, and status.
- **Device Details:** Camera type, firmware, serial, CPU & network usage.
- **MQTT Status:** Broker and topic configuration, connection health.
- **Application Info:** Name, version, vendor, support/documentation link.

Use this page as your *first check* when troubleshooting or confirming installation.

***

## Integration & Payload Examples

DetectX delivers three primary payload types, all enrichable with the configured device name, location, and serial for easy association in your backend systems.

### 1. Detection (Bounding Box) on MQTT

**Topic:**  
`detectx/detection/<serial>`

**Example Payload:**
```json
{
  "detections": [
    {
      "label": "car",
      "c": 77,
      "x": 274,
      "y": 224,
      "w": 180,
      "h": 104,
      "timestamp": 1756453942980,
      "refId": 260
    }
  ],
  "name": "Front",
  "location": "",
  "serial": "B8A44F3024BB"
}
```

***

### 2. Event State on MQTT or ONVIF

**Topic:**  
`detectx/event/<serial>/<label>/<state>`

**Example Payload:**
```json
{
  "label": "car",
  "state": false,
  "timestamp": 1756453946184,
  "name": "Front",
  "location": "",
  "serial": "B8A44F3024BB"
}
```

***

### 3. Detection Crop Image

**MQTT/HTTP Topic or POST:**  
`detectx/crop/<serial>`

**Example Payload:**
```json
{
  "label": "truck",
  "timestamp": 1756454378759,
  "confidence": 47,
  "x": 25,
  "y": 25,
  "w": 218,
  "h": 106,
  "image": "/9j/4AAQSk...",  // JPEG in Base64
  "name": "Front",
  "location": "",
  "serial": "B8A44F3024BB"
}
```

***

## System Integrator Tips

- **Start with the About page** to confirm firmware, model, and MQTT status before field adjustments.
- Use Detection and Crops pages for rapid troubleshooting—verify detections visually before integrating triggers or actions.
- Use unique device names/locations in MQTT setup for scalable multi-camera deployments.
- Adjust event suppression and AOI settings based on site/scene context for best accuracy.

***

## Troubleshooting & Support

- If bounding boxes do not appear but the model status is OK, check confidence, AOI, and MQTT broker configuration.
- If crop images are misaligned or cut-off, adjust crop borders and AOI, validating via the “View the latest crops” gallery.
- Monitor CPU and network on the About page to avoid overload (especially on ARTPEC-8 devices).

***

## Version History

## 5.1.0

Everything since 5.0.0; the 5.0.1 and 5.2.0-5.4.0 development builds are included.

### Two-tier detection
- **Two-tier models:** a detector finds objects in every frame, a classifier labels each
  one from a crop. Events, MQTT and crops use the classifier's label; `detector_c` keeps
  the detector's score.
- **Stage 2 reads the camera's full resolution:** crops come from a second stream at the
  largest 16:9 resolution of the active capture mode (setting `classifierHighRes`).
- **Classifier threshold** with a fallback label: below `classifierConfidence` the label
  becomes `classifierFallbackLabel`. The payload adds `classifier_label`, `classifier_c`
  and `classifier_fallback` only when the fallback replaced the label.
- **Default model: HandGesture's** hand detector (Hands v4 960x544 on ARTPEC-8, Hands v5
  1280x736 on ARTPEC-9) and 15-gesture classifier, with matching default settings.

### Detection and events
- **Event trigger by time-based vote** ("Prioritize"), with a new **Balanced** option.
  Speed fires on the first frame. Balanced fires when a label is in >= 75 % of the frames
  with detections within 300 ms; Accuracy when it is in >= 3 frames and >= 60 % within
  500 ms. Both also require that no other label was seen more often, so brief
  misclassifications do not fire. Settings `eventLogic` `{window, frames, share}` override.
- **View Areas:** run detection on one of the camera's View Areas (**View** on the live
  page). Stage 2 and exported crops still come from the full sensor.
- **No hidden minimum-size filter** (a 20/1000 default kept dropping small objects).
- Confidence and NMS changes apply immediately.

### Detection export
- Crops from the full-resolution stream (setting `cropping.fullResolution`); the payload
  adds `frame_w`/`frame_h`; crops are only cut when the throttle lets one out.

### Web UI
- Live view shows **FPS**; pages opened while the app starts wait and reload when the
  model is ready; About shows the MQTT topics actually published.

### Fixes
- No crash on stop or restart (double frees of status/device/MQTT settings; video threads
  and web requests running during shutdown).
- A failed inference no longer crashes the application into a restart loop.

### Repository
- Application only: `tools/install-model.sh` (two-tier model package -> `app/model/`,
  checked), `tools/check-model.sh` (detector + classifier contract check in Docker),
  `tools/camera.sh`, benchmarks in `tools/`; [docs/MODEL_CONTRACT.md](docs/MODEL_CONTRACT.md),
  [docs/BUILDING.md](docs/BUILDING.md), AGENTS.md.
- Model files renamed: `model-<chip>.tflite`, `classifier-<chip>.tflite`, `labels.txt`,
  `classifier-labels.txt` (were `<chip>-tier1/2.tflite`, `tier1/2-labels.txt`).
- Training and export moved to acap-model-pipeline (`export_yolov8.py`,
  `export_resolutions.sh`, `Train-Build.md`, COCO checkpoints).

## 5.0.0

First YOLOv8 release. The YOLOv5 line (4.x) is frozen at 4.1.1 and no longer maintained.

### Breaking changes
- **YOLOv8 replaces YOLOv5.** Anchor-free head with two output tensors
  (`[1,4,N]` coordinates and `[1,classes,N]` scores) instead of one fused
  `[1,N,5+classes]`, and no objectness column. 4.x models will not load on 5.x.
- **Separate ARTPEC-8 and ARTPEC-9 packages.** The A8 DLPU requires per-tensor
  weight quantization, the A9 uses per-channel; the two are not interchangeable.
  Previously a single package served both.
- Models must be exported with `export_yolov8.py`, which produces uint8 I/O and the
  split coordinate/score tensors the runtime needs. Ultralytics' built-in TFLite
  export (float32 I/O, one fused tensor) cannot be decoded by this application.

### New
- Default model is **YOLOv8n COCO at 640x384** -- fast (~20 fps on ARTPEC-8) and
  16:9 to match the scene. See **Choosing a configuration** for when to change it.
- Built against the current Axis ACAP SDK (manifest schema 2.2.0), DLPU declared as
  a required resource, `runMode: respawn`.
- The application introspects the model at startup (input size, class count,
  quantization), so any exported model drops in without code changes.
- `export_resolutions.sh` / `benchmark_resolutions.sh` / `benchmark_larod.sh` for
  exporting a model across resolutions and measuring latency on your own camera.
- Model load is deferred past application start so the web UI stays responsive and
  reports "Loading model" during the 30-60 s cold start instead of appearing hung.
- PyTorch checkpoints for the shipped models are in `models/`.

### Fixes
- Corrected a double-free in larod teardown that aborted the process on every stop.

### Requirements
- **ARTPEC-9 requires Axis OS 13 or later.**

---

## Legacy YOLOv5 Releases

DetectX 5.x does not support YOLOv5 models. For an existing YOLOv5 deployment or
further work on that model format, use the frozen legacy line instead:

- **Latest legacy release:** [v4.1.1](https://github.com/pandosme/DetectX/tree/v4.1.1)
- **Legacy development branch:** [4.1.0](https://github.com/pandosme/DetectX/tree/4.1.0)

```bash
git checkout v4.1.1  # last YOLOv5 release
# or
git checkout 4.1.0   # legacy development branch
```

The 4.x line is not compatible with v5 models or packages, and receives no new
features.

## 4.1.1

- Fixed EAP release-asset publishing.

## 4.1.0

- Added polygon AOI and exclusion zones, runtime model upload, SD-card training
  capture, and bounding-box overlay fixes.

## 4.0.0 - February 2, 2026

- Moved from normalized coordinates to model-input pixel coordinates.
- Added automatic migration for existing AOI and size-filter settings.
- Redesigned the web UI with top navigation and card-based layouts.
- Removed the old `prepare.py` dependency; model parameters were extracted during
  the Docker build.

## 3.5.3 - November 29, 2025

- Fixed a memory leak.

## 3.5.2 - August 29, 2025

- Fixed black-box video on selected cameras.

## 3.5.1 - August 29, 2025

- Added Detection Export, GUI updates, and MQTT improvements.

## 3.4.0 - May 14, 2025

- Cleaned up MQTT handling and fixed GUI and MQTT connection issues.

## 3.3.10 - March 4, 2025

- Refactored MQTT support.

## 3.3.8 - February 27, 2025

- Fixed a detection-page crash and MQTT stability issues.
- Added MQTT connect messages and more last-will properties.

## 3.3.7 - February 22, 2025

- Improved MQTT stability and UI feedback for unsupported platforms, model
  loading, and unavailable applications.

## 3.3.6 - February 7, 2025

- Fixed a UI-related crash during extended use.

## 3.3.5 - February 2025

- Fixed a serious memory leak and expanded About-page information.

## 3.3.0 - December 21, 2024

- Added MQTT support.

## 3.2.0 - December 20, 2024

- Updated the ACAP wrapper to 3.2.0.

## 3.1.5 - December 11, 2024

- Fixed event handling.

## 3.1.0 - November 27, 2024

- Updated the ACAP SDK, refactored application files, and added per-label
  events and visualization improvements.

## 2.2.0 - October 19, 2024

- Added the Label Counter event and fixed detection transitions.

## 2.1.1 - October 13, 2024

- Fixed event states and a potential memory leak.

## 2.1.0 - October 11, 2024

- Added detection transitions and removed SD-card detection-image storage.

## 1.2.0 - October 7, 2024

- Added minimum-size filtering and fixed multiple detections in one scene.

## 1.0.3 - September 15, 2024

- Restructured model and settings configuration.

## 1.0.2 - September 7, 2024

- Fixed detection and SD-card image-storage issues.

## 1.0.1 - September 6, 2024

- Restructured SD-card detection-image storage and fixed reset behavior.

## 1.0.0 - September 5, 2024

- Initial release.
