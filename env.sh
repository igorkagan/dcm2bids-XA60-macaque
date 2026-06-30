# Source once per shell session from the repo root:
#   source /mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque/env.sh
#
# Sets path roots and activates the WSL conda env "bids".

export REPO_ROOT="/mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque"
export MRI_DATA_ROOT="/home/ikagan/mri"

CONDA_BASE="$(conda info --base 2>/dev/null || true)"
if [[ -z "${CONDA_BASE}" ]]; then
    echo "ERROR: conda not found on PATH." >&2
    return 1 2>/dev/null || exit 1
fi
# shellcheck disable=SC1091
source "${CONDA_BASE}/etc/profile.d/conda.sh"
conda activate bids
