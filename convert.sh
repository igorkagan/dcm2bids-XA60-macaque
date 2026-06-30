#!/usr/bin/env bash
# DICOM -> BIDS conversion (Siemens MAGNETOM Prisma, XA60).
#
# Idempotent: re-runs cleanly. The BIDS scaffold is created on first run
# and preserved on subsequent runs; only sub-<label>/ is rebuilt.
#
# Usage:
#   source env.sh && source studies/mac_1180.env
#   ./convert.sh 01
#
#   ./convert.sh 01 /path/to/dicom /path/to/bids_out
#
# DICOM_DIR and BIDS_DIR must be set (study .env) or passed as args 2 and 3.
# Exits non-zero on conversion or validation failure.

set -euo pipefail

SUBJECT="${1:-01}"

if [[ -n "${2:-}" ]]; then
    DICOM_DIR="$2"
elif [[ -n "${DICOM_DIR:-}" ]]; then
    :
else
    echo "ERROR: set DICOM_DIR (source studies/<study>.env) or pass as arg 2" >&2
    exit 1
fi

if [[ -n "${3:-}" ]]; then
    BIDS_DIR="$3"
elif [[ -n "${BIDS_DIR:-}" ]]; then
    :
else
    echo "ERROR: set BIDS_DIR (source studies/<study>.env) or pass as arg 3" >&2
    exit 1
fi
export DICOM_DIR BIDS_DIR

CODE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${CODE_DIR}/config.json"
DCM2BIDS_LOG="${CODE_DIR}/dcm2bids.log"
VALIDATOR_LOG="${CODE_DIR}/bids-validator.log"

CONDA_BASE="$(conda info --base 2>/dev/null || true)"
if [[ -z "${CONDA_BASE}" ]]; then
    echo "ERROR: conda not found on PATH." >&2
    exit 1
fi
# shellcheck disable=SC1091
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate bids

for bin in dcm2bids dcm2bids_scaffold dcm2niix bids-validator python; do
    command -v "${bin}" >/dev/null 2>&1 || { echo "ERROR: ${bin} missing from PATH" >&2; exit 1; }
done

[[ -d "${DICOM_DIR}" ]] || { echo "ERROR: DICOM dir not found: ${DICOM_DIR}" >&2; exit 1; }
[[ -f "${CONFIG}"   ]] || { echo "ERROR: config not found: ${CONFIG}"       >&2; exit 1; }

echo "=== DICOM -> BIDS ==="
echo "  subject : sub-${SUBJECT}"
echo "  dicom   : ${DICOM_DIR}"
echo "  bids    : ${BIDS_DIR}"
echo "  config  : ${CONFIG}"
echo

if [[ ! -f "${BIDS_DIR}/dataset_description.json" ]]; then
    mkdir -p "${BIDS_DIR}"
    echo "[scaffold] creating BIDS skeleton in ${BIDS_DIR}"
    dcm2bids_scaffold -o "${BIDS_DIR}"
fi

echo "[convert] running dcm2bids (logs -> ${DCM2BIDS_LOG})"
dcm2bids \
    -d "${DICOM_DIR}" \
    -p "${SUBJECT}" \
    -c "${CONFIG}" \
    -o "${BIDS_DIR}" \
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
