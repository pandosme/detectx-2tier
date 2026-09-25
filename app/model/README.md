# Model artifacts

A two-tier package requires these files before building:

- `model-a8.tflite` and `model-a9.tflite`: split-output uint8 YOLOv8 detectors.
- `labels.txt`: detector labels in model output order.
- `classifier-a8.tflite` and `classifier-a9.tflite`: uint8 RGB classifiers with one uint8 class-score output.
- `classifier-labels.txt`: classifier labels in output order.

`acap-model-pipeline` writes target-specific detector and classifier files. Copy or rename
its detector outputs to `model-a8.tflite`/`model-a9.tflite`, classifier outputs to
`classifier-a8.tflite`/`classifier-a9.tflite`, and keep their two label files separate.

The classifier training crop margin must match `classifierCropMargin` in
`app/settings/settings.json`.
