#!/usr/bin/env bash
# DICOM -> BIDS with auto-generated config (no manual config.json editing).
#
# Usage:
#   ./convert_auto.sh /path/to/dicom [subject] [bids_out]
#
# Defaults: subject=01, bids_out=<parent-of-dicom>/bids
# Optional: place SeriesInfos.txt next to dicom/ for mismatch warnings only.

set -euo pipefail

DICOM_DIR="${1:?usage: convert_auto.sh <dicom_dir> [subject] [bids_out]}"
SUBJECT="${2:-01}"
BIDS_DIR="${3:-$(dirname "${DICOM_DIR}")/bids}"

CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ROOT="$(mktemp -d)"
CONFIG="${BIDS_DIR}/code/dcm2bids_config.generated.json"
DCM2BIDS_LOG="${CODE_DIR}/dcm2bids.log"
VALIDATOR_LOG="${CODE_DIR}/bids-validator.log"

cleanup() { rm -rf "${HELPER_ROOT}"; }
trap cleanup EXIT

CONDA_BASE="$(conda info --base 2>/dev/null || true)"
if [[ -z "${CONDA_BASE}" ]]; then
    echo "ERROR: conda not found on PATH." >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate bids

for bin in dcm2bids dcm2bids_helper dcm2bids_scaffold bids-validator python; do
    command -v "${bin}" >/dev/null 2>&1 || { echo "ERROR: ${bin} missing from PATH" >&2; exit 1; }
done

[[ -d "${DICOM_DIR}" ]] || { echo "ERROR: DICOM dir not found: ${DICOM_DIR}" >&2; exit 1; }

SERIES_INFO=""
for candidate in \
    "${DICOM_DIR}/SeriesInfos.txt" \
    "${DICOM_DIR%/}/../SeriesInfos.txt" \
    "${DICOM_DIR%/}/../studies/"*"/SeriesInfos.txt"; do
    [[ -f "${candidate}" ]] && SERIES_INFO="${candidate}" && break
done

echo "=== DICOM -> BIDS (auto config) ==="
echo "  subject : sub-${SUBJECT}"
echo "  dicom   : ${DICOM_DIR}"
echo "  bids    : ${BIDS_DIR}"
[[ -n "${SERIES_INFO}" ]] && echo "  series  : ${SERIES_INFO} (warnings only)"
echo

mkdir -p "${BIDS_DIR}"

echo "[helper] running dcm2bids_helper"
dcm2bids_helper -d "${DICOM_DIR}" -o "${HELPER_ROOT}" --force

HELPER_JSON="${HELPER_ROOT}/tmp_dcm2bids/helper"
[[ -d "${HELPER_JSON}" ]] || { echo "ERROR: helper output missing: ${HELPER_JSON}" >&2; exit 1; }

if [[ ! -f "${BIDS_DIR}/dataset_description.json" ]]; then
    echo "[scaffold] creating BIDS skeleton"
    dcm2bids_scaffold -o "${BIDS_DIR}"
fi

README="${BIDS_DIR}/README"
if [[ ! -s "${README}" ]]; then
    echo "BIDS dataset converted from Siemens XA60 Enhanced DICOM via dcm2bids-XA60-macaque." > "${README}"
fi

mkdir -p "${BIDS_DIR}/code"

echo "[config] generating ${CONFIG}"
GEN_ARGS=("${CODE_DIR}/gen_config.py" "${HELPER_JSON}" -o "${CONFIG}")
[[ -n "${SERIES_INFO}" ]] && GEN_ARGS+=(--series-info "${SERIES_INFO}")
python "${GEN_ARGS[@]}"

echo "[convert] running dcm2bids (logs -> ${DCM2BIDS_LOG})"
dcm2bids \
    -d "${DICOM_DIR}" \
    -p "${SUBJECT}" \
    -c "${CONFIG}" \
    -o "${BIDS_DIR}" \
    --clobber \
    --force_dcm2bids 2>&1 | tee "${DCM2BIDS_LOG}"

echo
echo "[validate] running bids-validator (logs -> ${VALIDATOR_LOG})"
set +e
bids-validator "${BIDS_DIR}" 2>&1 | tee "${VALIDATOR_LOG}"
validator_rc=${PIPESTATUS[0]}
set -e
if [[ ${validator_rc} -ne 0 ]]; then
    echo "ERROR: bids-validator failed (rc=${validator_rc}). See ${VALIDATOR_LOG}" >&2
    exit "${validator_rc}"
fi

echo
echo "[QC] sidecar summary"
ANAT_DIR="${BIDS_DIR}/sub-${SUBJECT}/anat"
if [[ -d "${ANAT_DIR}" ]]; then
    python - <<PYEOF
import json, glob, os
anat = "${ANAT_DIR}"
keys = ["SeriesNumber", "SeriesDescription", "RepetitionTime",
        "EchoTime", "FlipAngle", "InversionTime"]
header = ["file"] + keys + ["NORM"]
print("\t".join(header))
for p in sorted(glob.glob(os.path.join(anat, "*.json"))):
    with open(p) as f:
        j = json.load(f)
    norm = "NORM" in (j.get("ImageTypeText") or [])
    row = [os.path.basename(p)] + [str(j.get(k)) for k in keys] + [str(norm)]
    print("\t".join(row))
PYEOF
else
    echo "  (no anat dir found at ${ANAT_DIR})"
fi

echo
echo "=== done ==="
echo "  config : ${CONFIG}"
