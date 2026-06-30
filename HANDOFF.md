# Handoff — mac_1180, XA60 macaque

## Subject

- **ID:** mac_1180 (pilot)
- **Scanner:** Siemens MAGNETOM Prisma, syngo MR XA60
- **DICOM:** Enhanced MR, 1 file per series
- **Data:** `/home/ikagan/mri/mac_1180/dicom/`

## Series decisions

See [`studies/mac_1180/SeriesInfos.txt`](studies/mac_1180/SeriesInfos.txt).

| SN | BIDS target |
|----|-------------|
| 2 | `run-01_rec-orig_T1w` |
| 3 | `run-01_rec-norm_T1w` |
| 4 | `run-02_rec-orig_T1w` |
| 5 | `run-02_rec-norm_T1w` |
| 1004 | `acq-mean35_T1w` (MEAN of SN 3 + 5) |

Excluded: SN 1 (localizer), SN 99 (PhoenixZIP).

### SN ≥ 1000 rule

Siemens exports on-scanner **MEAN** composites with series numbers ≥ 1000.
SN **1004** DICOM header = `MEAN_3_5` = average of SN **3** and **5** (both
rec-norm). `config.json` uses `search_method: re` so known `MEAN_X_Y` patterns
map to `acq-meanXY`; unmatched 10xx means get generic `acq-mean`. Add a new
description block when a novel `MEAN_A_B` pair appears and update the catch-all
negative lookahead if needed.

## config.json matching

Unlike human (one orig/norm pair per contrast), mac_1180 has **two repeat runs**
with identical `SeriesDescription`. Criteria require **SeriesNumber** plus
position-aware `ImageTypeText`:

- NORM (5 elements): `["*", "*", "*", "NORM", "*"]`
- plain (4 elements): `["*", "*", "*", "*"]`

See [human HANDOFF](https://github.com/igorkagan/dcm2bids-XA60-human) for shared
XA60 gotchas (`compare_list` length, no `auto_extract_entities`, scaffold step).

## Repo layout

- Code: `/mnt/e/Dropbox/Sources/Repos/dcm2bids-XA60-macaque`
- Data stays outside repo under `/home/ikagan/mri/mac_1180/`
