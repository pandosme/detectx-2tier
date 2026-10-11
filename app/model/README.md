# Model artifacts

A two-tier package requires these files before building. Tier 1 is the detector
that runs every frame; tier 2 is the classifier that runs once per detected box.
The chip prefix selects the DLPU build (`a8` = ARTPEC-8, `a9` = ARTPEC-9).

- `a8-tier1.tflite` and `a9-tier1.tflite`: split-output uint8 YOLOv8 detectors.
- `tier1-labels.txt`: detector labels in model output order.
- `a8-tier2.tflite` and `a9-tier2.tflite`: uint8 RGB classifiers with one uint8 class-score output.
- `tier2-labels.txt`: classifier labels in output order.

The label files are chip-independent. At build time the Dockerfile stages the selected
chip's files as the runtime names `model.tflite`, `labels.txt`, `classifier.tflite` and
`classifier-labels.txt` inside the package, so the application code never sees the chip prefix.

`acap-model-pipeline` writes target-specific detector and classifier files. Copy or rename
its detector outputs to `a8-tier1.tflite`/`a9-tier1.tflite`, classifier outputs to
`a8-tier2.tflite`/`a9-tier2.tflite`, and keep their two label files separate.

The classifier training crop margin must match `classifierCropMargin` in
`app/settings/settings.json`.
