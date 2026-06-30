#!/usr/bin/env bash
# Convert an entire study DICOM tree to NIfTI, split by modality.
#
# Usage:
#   source env.sh && source studies/IK2026.env
#   ./dicom2nii_study.sh                    # uses DICOM_DIR / NII_OUT from study env
#   ./dicom2nii_study.sh /path/dicom /path/nii_out
#
# Runs dcm2niix recursively, then sorts volumes into anat/swi/dwi/mra/ and
# removes per-frame MIP clutter (*_i[0-9]* — never *_iso_*).

set -euo pipefail

if [[ -n "${1:-}" ]]; then
    DICOM_DIR="$1"
elif [[ -n "${DICOM_DIR:-}" ]]; then
    :
else
    echo "ERROR: set DICOM_DIR (source studies/<study>.env) or pass as arg 1" >&2
    exit 1
fi

if [[ -n "${2:-}" ]]; then
    NII_OUT="$2"
elif [[ -n "${NII_OUT:-}" ]]; then
    :
else
    NII_OUT="${DICOM_DIR%/}/nii_out"
fi

[[ -d "${DICOM_DIR}" ]] || { echo "ERROR: not a directory: ${DICOM_DIR}" >&2; exit 1; }

CONDA_BASE="$(conda info --base 2>/dev/null || true)"
if [[ -z "${CONDA_BASE}" ]]; then
    echo "ERROR: conda not found on PATH." >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate bids

command -v dcm2niix >/dev/null 2>&1 || { echo "ERROR: dcm2niix missing" >&2; exit 1; }

mkdir -p "${NII_OUT}"

echo "dicom : ${DICOM_DIR}"
echo "output: ${NII_OUT}"
echo

dcm2niix -z y -b y -ba y -f "%3s_%p" -o "${NII_OUT}" "${DICOM_DIR}"

# Drop per-frame MIP/reformat exports (e.g. 009_pca3d_..._i09001).
# Must NOT match *_iso_* in filenames like t1_vibe_3D_iso_...
shopt -s nullglob
clutter=( "${NII_OUT}"/*_i[0-9]*.nii.gz "${NII_OUT}"/*_i[0-9]*.json )
if (( ${#clutter[@]} )); then
    echo "removing ${#clutter[@]} single-frame MIP files"
    rm -f "${clutter[@]}"
fi

mkdir -p "${NII_OUT}/anat" "${NII_OUT}/swi" "${NII_OUT}/dwi" "${NII_OUT}/mra"

classify() {
    local base="${1%.nii.gz}"
    base="${base%.json}"
    local name="${base##*/}"
    case "${name}" in
        *t2_tse*|*t1_mprage*|*t1_vibe*|*T1w*|*T2w*) echo anat ;;
        *t2_swi*|*SWI*|*swi*)                          echo swi  ;;
        *ep2d_diff*|*ADC*|*TRACEW*|*dwi*)              echo dwi  ;;
        *pca3d*|*tof_cs*|*TOF*|*PCA*)                  echo mra  ;;
        *)                                             echo ""   ;;
    esac
}

for f in "${NII_OUT}"/*.nii.gz "${NII_OUT}"/*.json; do
    [[ -f "$f" ]] || continue
    dest=$(classify "$f")
    if [[ -n "$dest" ]]; then
        mv "$f" "${NII_OUT}/${dest}/"
    fi
done

echo
echo "=== result ==="
for d in anat swi dwi mra; do
    count=$(find "${NII_OUT}/${d}" -maxdepth 1 -name '*.nii.gz' 2>/dev/null | wc -l)
    echo "  ${d}/: ${count} volumes"
done
left=$(find "${NII_OUT}" -maxdepth 1 -name '*.nii.gz' 2>/dev/null | wc -l)
if (( left > 0 )); then
    echo "  (root): ${left} unclassified — check ${NII_OUT}/"
fi
