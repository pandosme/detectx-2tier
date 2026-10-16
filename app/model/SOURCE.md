# Bundled models

The default model pair is HandGesture's (HandGesture 5.1.0): a hand detector and a
15-gesture classifier, trained on the HaGRID dataset plus real camera footage.

| File | Model | Input |
|---|---|---|
| model-a8.tflite | Hands v4 hand detector, YOLOv8n, 1 class (`hand`) | 960x544 |
| model-a9.tflite | Hands v5 hand detector, YOLOv8n, 1 class (`hand`) | 1280x736 |
| classifier-a8.tflite, classifier-a9.tflite | gesture15 classifier, YOLOv8s-cls, 15 classes | 128x128 |

The ARTPEC-8 detector uses the smaller input for frame rate; ARTPEC-9 uses the larger
one for range. Replace them with `tools/install-model.sh` (see docs/BUILDING.md); the
installer rewrites this file.

| File | SHA-256 |
|---|---|
| model-a8.tflite | 9605317c47f8c909... |
| model-a9.tflite | a5c1e1f51ba0cc3d... |
| classifier-a8.tflite | 80ea1f9ae48ea0c1... |
| classifier-a9.tflite | 7424cc4c9302652d... |
| labels.txt | fad6926e5d29328d... |
| classifier-labels.txt | 60319b001611fc39... |

Detector labels: hand

Classifier labels: call, dislike, fist, four, like, middle_finger, mute, no_gesture, ok, one, palm, peace, rock, stop, three
