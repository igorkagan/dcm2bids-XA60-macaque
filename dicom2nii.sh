#!/usr/bin/env bash
# Convert one anatomical DICOM series (multislice) to NIfTI.
# No BIDS layout, no dcm2bids — just dcm2niix.
#
# Usage:
#   ./dicom2nii.sh /path/to/dicom/series                    # -> <dicom_dir>/nii_out/
#   ./dicom2nii.sh /path/to/dicom/series /path/to/out
#
# Point DICOM_DIR at a folder containing only the series you want.
# If several series share the folder, dcm2niix will emit one NIfTI per series.

set -euo pipefail

DICOM_DIR="${1:?usage: dicom2nii.sh <dicom_dir> [output_dir]}"
OUT_DIR="${2:-${DICOM_DIR%/}/nii_out}"

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

mkdir -p "${OUT_DIR}"

echo "dicom : ${DICOM_DIR}"
echo "output: ${OUT_DIR}"
echo

dcm2niix \
    -z y \
    -b y \
    -ba y \
    -f "%p" \
    -o "${OUT_DIR}" \
    "${DICOM_DIR}"

echo
echo "written:"
ls -lh "${OUT_DIR}"/*.{nii,nii.gz,json} 2>/dev/null || ls -lh "${OUT_DIR}/"
