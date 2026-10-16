#!/bin/bash
#
# Install a trained two-tier model (detector + classifier) into the ACAP before building.
#
#   tools/install-model.sh <model-package-dir> [--size WxH] [--no-check]
#   tools/install-model.sh --a8 <a8.tflite> --a9 <a9.tflite> --labels <labels.txt> \
#       --classifier-a8 <a8.tflite> --classifier-a9 <a9.tflite> --classifier-labels <labels.txt>
#
# A model package is the folder acap-model-pipeline produces (docs/MODEL_CONTRACT.md):
# labels.txt plus one detector per chip and input size (mymodel-a8-960x544.tflite, ...),
# and a classifier/ folder with labels.txt and one classifier per chip
# (mymodel-classifier-a8-128x128.tflite, ...). With several detector sizes, choose one
# with --size. Options given on the command line replace files from the package.
#
# The files are copied to the names the build uses -- app/model/model-<chip>.tflite,
# labels.txt, classifier-<chip>.tflite, classifier-labels.txt -- after each chip's pair
# is checked against the model contract (tools/check-model.sh, needs Docker).
# app/model/SOURCE.md records where the bundled models came from. Then run ./build.sh.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODEL_DIR="$ROOT/app/model"
PKG='' SIZE='' CHECK=1 LABELS='' CLABELS=''
declare -A SRC=() CLS=()

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
	case "$1" in
		--size) SIZE=${2:?--size needs WxH}; shift 2 ;;
		--a8|--a9) SRC[${1#--}]=${2:?$1 needs a file}; shift 2 ;;
		--labels) LABELS=${2:?--labels needs a file}; shift 2 ;;
		--classifier-a8|--classifier-a9) CLS[${1#--classifier-}]=${2:?$1 needs a file}; shift 2 ;;
		--classifier-labels) CLABELS=${2:?--classifier-labels needs a file}; shift 2 ;;
		--no-check) CHECK=0; shift ;;
		-h|--help) usage; exit 0 ;;
		-*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
		*) PKG=$1; shift ;;
	esac
done

if [ -n "$PKG" ]; then
	[ -d "$PKG" ] || { echo "Not a directory: $PKG" >&2; exit 1; }
	PKG=$(cd "$PKG" && pwd)
	if [ -z "$LABELS" ]; then
		if [ -f "$PKG/labels.txt" ]; then LABELS="$PKG/labels.txt"
		else
			mapfile -t found < <(find "$PKG" -maxdepth 1 -name '*labels*.txt' | sort)
			[ ${#found[@]} -eq 1 ] || { echo "Expected labels.txt in $PKG" >&2; exit 1; }
			LABELS=${found[0]}
		fi
	fi
	for chip in a8 a9; do
		[ -n "${SRC[$chip]:-}" ] && continue
		mapfile -t found < <(find "$PKG" -maxdepth 1 -name '*.tflite' \
			\( -name "${chip}-*" -o -name "*-${chip}-*" -o -name "*-${chip}.tflite" -o -name "*_${chip}*" \) | sort)
		if [ -n "$SIZE" ]; then
			mapfile -t found < <(printf '%s\n' "${found[@]}" | grep -F -- "$SIZE" || true)
		fi
		if [ ${#found[@]} -gt 1 ]; then
			echo "Several ${chip} models in $PKG; choose one with --size:" >&2
			printf '  %s\n' "${found[@]##*/}" >&2
			exit 1
		fi
		[ ${#found[@]} -eq 1 ] && [ -n "${found[0]}" ] && SRC[$chip]=${found[0]}
	done
	if [ -d "$PKG/classifier" ]; then
		[ -n "$CLABELS" ] || CLABELS="$PKG/classifier/labels.txt"
		for chip in a8 a9; do
			[ -n "${CLS[$chip]:-}" ] && continue
			mapfile -t found < <(find "$PKG/classifier" -maxdepth 1 -name "*-${chip}-*.tflite" | sort)
			[ ${#found[@]} -gt 1 ] && { echo "Several ${chip} classifiers in $PKG/classifier" >&2; exit 1; }
			[ ${#found[@]} -eq 1 ] && [ -n "${found[0]}" ] && CLS[$chip]=${found[0]}
		done
	fi
fi

[ -n "$LABELS" ] && [ -f "$LABELS" ] || { echo "No labels file given or found" >&2; usage >&2; exit 1; }
[ -n "${SRC[a8]:-}${SRC[a9]:-}" ] || { echo "No ARTPEC-8 or ARTPEC-9 model found${SIZE:+ for $SIZE}" >&2; exit 1; }
for chip in a8 a9; do
	if [ -n "${SRC[$chip]:-}" ] && [ -z "${CLS[$chip]:-}" ]; then
		echo "No ${chip} classifier: a two-tier package needs classifier/ (or --classifier-${chip})" >&2; exit 1
	fi
done
[ -n "$CLABELS" ] && [ -f "$CLABELS" ] || { echo "No classifier labels given or found" >&2; exit 1; }

if [ "$CHECK" -eq 1 ]; then
	for chip in a8 a9; do
		[ -n "${SRC[$chip]:-}" ] || continue
		echo "== Checking ${SRC[$chip]##*/} for ARTPEC-${chip#a}"
		"$ROOT/tools/check-model.sh" "${SRC[$chip]}" "$LABELS" --target "$chip" \
			--classifier "${CLS[$chip]}" "$CLABELS"
	done
fi

mkdir -p "$MODEL_DIR"
cp "$LABELS" "$MODEL_DIR/labels.txt"
cp "$CLABELS" "$MODEL_DIR/classifier-labels.txt"
for chip in a8 a9; do
	if [ -n "${SRC[$chip]:-}" ]; then
		cp "${SRC[$chip]}" "$MODEL_DIR/model-${chip}.tflite"
		cp "${CLS[$chip]}" "$MODEL_DIR/classifier-${chip}.tflite"
	else
		echo "WARNING: no ARTPEC-${chip#a} model given; app/model/model-${chip}.tflite is unchanged and may not match the new labels." >&2
	fi
done

{
	echo "# Bundled models"
	echo
	echo "Installed $(date -u +%Y-%m-%dT%H:%M:%SZ) by tools/install-model.sh."
	echo
	[ -n "$PKG" ] && echo "Package: \`$PKG\`${SIZE:+ (size $SIZE)}" && echo
	if [ -n "$PKG" ] && [ -f "$PKG/model.json" ]; then
		echo '```json'; cat "$PKG/model.json"; echo '```'; echo
	fi
	echo "| File | Source | SHA-256 |"
	echo "|---|---|---|"
	for chip in a8 a9; do
		f="$MODEL_DIR/model-${chip}.tflite"
		[ -f "$f" ] || continue
		echo "| model-${chip}.tflite | ${SRC[$chip]:-(unchanged)} | $(sha256sum "$f" | cut -c1-16)... |"
		f="$MODEL_DIR/classifier-${chip}.tflite"
		[ -f "$f" ] && echo "| classifier-${chip}.tflite | ${CLS[$chip]:-(unchanged)} | $(sha256sum "$f" | cut -c1-16)... |"
	done
	echo "| labels.txt | $LABELS | $(sha256sum "$MODEL_DIR/labels.txt" | cut -c1-16)... |"
	echo "| classifier-labels.txt | $CLABELS | $(sha256sum "$MODEL_DIR/classifier-labels.txt" | cut -c1-16)... |"
	echo
	echo "Detector labels ($(grep -c . "$MODEL_DIR/labels.txt")): $(grep . "$MODEL_DIR/labels.txt" | paste -sd, - | sed 's/,/, /g')"
	echo
	echo "Classifier labels ($(grep -c . "$MODEL_DIR/classifier-labels.txt")): $(grep . "$MODEL_DIR/classifier-labels.txt" | paste -sd, - | sed 's/,/, /g')"
} > "$MODEL_DIR/SOURCE.md"

echo "Installed into app/model/:"
for chip in a8 a9; do
	[ -n "${SRC[$chip]:-}" ] || continue
	echo "  model-${chip}.tflite       <- ${SRC[$chip]}"
	echo "  classifier-${chip}.tflite  <- ${CLS[$chip]}"
done
echo "  classifier-labels.txt     <- $CLABELS ($(grep -c . "$MODEL_DIR/classifier-labels.txt") labels)"
echo "  labels.txt           <- $LABELS ($(grep -c . "$MODEL_DIR/labels.txt") labels)"
echo "Next: ./build.sh"
