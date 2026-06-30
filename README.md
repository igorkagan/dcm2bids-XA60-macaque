# dcm2bids-XA60-macaque

Tooling for converting **Siemens MAGNETOM Prisma syngo MR XA60 Enhanced DICOM**
(macaque scans) into BIDS or NIfTI.

Sibling repo: [dcm2bids-XA60-human](https://github.com/igorkagan/dcm2bids-XA60-human)
(human structural pilot — shared WSL workflow, different `config.json`).

**Code:** `E:\Dropbox\Sources\Repos\dcm2bids-XA60-macaque`  
**WSL:** `/mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque`  
**Pilot data:** `/home/ikagan/mri/mac_1180/`

---

## WSL + Windows layout

| Role | Windows | WSL |
|------|---------|-----|
| Git repo | `E:\Dropbox\Sources\Repos\dcm2bids-XA60-macaque` | `/mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque` |
| Study data | (pilot) WSL home | `/home/ikagan/mri/mac_1180/` |
| Tools | — | conda env `bids` |

```bash
cd /mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque
source env.sh
./convert_auto.sh /home/ikagan/mri/mac_1180/dicom 01
# writes BIDS to ../bids by default; config saved in bids/code/
```

Manual config path (legacy):

```bash
source env.sh && source studies/mac_1180.env
./convert.sh 01
```

Open this folder in Cursor via the **WSL path**, not `\\wsl.localhost\...` UNC.

---

## Series inventory — mac_1180

From [`studies/mac_1180/SeriesInfos.txt`](studies/mac_1180/SeriesInfos.txt):

| SN | #dcms | Description | Action |
|----|-------|-------------|--------|
| 1 | 1 | `localizer_sag+cor+tra` | exclude |
| 2 | 1 | `t1_tfl3d_ns_tra_850TI_8deg_0.5mm_fatsat_psn` | **run-01 rec-orig T1w** |
| 3 | 1 | same (NORM reconstruction) | **run-01 rec-norm T1w** |
| 4 | 1 | same | **run-02 rec-orig T1w** |
| 5 | 1 | same (NORM reconstruction) | **run-02 rec-norm T1w** |
| 99 | 3 | `PhoenixZIPReport` | exclude |
| 1004 | 2 | `MEAN_3_5_t1_tfl3d_...` | **acq-mean35 T1w** — mean of SN 3 and 5 |

### SN ≥ 1000 — Siemens on-scanner averages

Any series number **≥ 1000** is a **scanner-computed average** of earlier primary
series. Source series are encoded in the `MEAN_X_Y` prefix of `SeriesDescription`
(column 8 in `SeriesInfos.txt`; DICOM header is authoritative).

- **SN 1004** = `MEAN_3_5` → pixel-wise mean of **SN 3 and SN 5** (the two
  `rec-norm` volumes from run-01 and run-02).
- Sidecars: `ImageTypeText` ends with `MEAN`; six-element list vs four/five for primaries.
- **`config.json`** maps known `MEAN_X_Y` patterns to `acq-meanXY` in `anat/`;
  any other 10xx `MEAN_*` series falls through to generic `acq-mean`.

### Acquisition parameters (from sidecars)

- TR 2.7 s, TE 2.96 ms, FA 8°, TI 850 ms, 0.5 mm isotropic T1w
- Protocol: `t1_tfl3d_ns_tra_850TI_8deg_0.5mm_fatsat_psn`

### BIDS entity rationale

Two repeat T1 scans (run-01, run-02), each exported twice (without / with Prescan
Normalize filter). Same `SeriesDescription` for SN 2–5, so matching uses
**SeriesNumber** plus **ImageTypeText** NORM position (same `compare_list`
length rules as the human repo).

Expected output:

```
mac_1180/bids/sub-01/anat/
├── sub-01_rec-orig_run-01_T1w.{nii.gz,json}
├── sub-01_rec-norm_run-01_T1w.{nii.gz,json}
├── sub-01_rec-orig_run-02_T1w.{nii.gz,json}
├── sub-01_rec-norm_run-02_T1w.{nii.gz,json}
└── sub-01_acq-mean35_T1w.{nii.gz,json}
```

---

## Contents

| File | Purpose |
|------|---------|
| `env.sh` | Path roots + conda `bids` |
| `convert_auto.sh` | **DICOM → BIDS, auto config** (recommended) |
| `gen_config.py` | Sidecar → config.json (used by convert_auto) |
| `config.json` | Manual dcm2bids config (legacy / reference) |
| `convert.sh` | DICOM → BIDS using manual `config.json` |
| `dicom2nii.sh` | Single-series → NIfTI |
| `dicom2nii_study.sh` | Whole study → NIfTI by modality |
| `studies/mac_1180/` | SeriesInfos.txt reference |

---

## Requirements

Same as human repo — conda env `bids` with `dcm2bids` 3.2, `dcm2niix`,
`bids-validator`. See human README for install commands.
