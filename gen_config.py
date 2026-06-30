#!/usr/bin/env python3
"""Auto-generate dcm2bids config.json from dcm2bids_helper sidecar JSONs."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

SKIP_RE = re.compile(
    r"localizer|phoenix|survey|adjso|report|screensave",
    re.IGNORECASE,
)
MEAN_RE = re.compile(r"^MEAN_(\d+)_(\d+)_")

DCM2NIIX_OPTIONS = "-b y -ba y -z y -f '%3s_%p'"


def load_sidecars(helper_dir: Path) -> list[dict]:
    sidecars = []
    for path in sorted(helper_dir.glob("*.json")):
        with path.open() as f:
            data = json.load(f)
        sidecars.append(data)
    if not sidecars:
        raise SystemExit(f"ERROR: no JSON sidecars in {helper_dir}")
    return sidecars


def is_norm(image_type_text: list[str] | None) -> bool:
    return bool(image_type_text and "NORM" in image_type_text)


def is_mean(sidecar: dict) -> bool:
    desc = sidecar.get("SeriesDescription") or ""
    if MEAN_RE.match(desc):
        return True
    sn = sidecar.get("SeriesNumber")
    itt = sidecar.get("ImageTypeText") or []
    return sn is not None and sn >= 1000 and "MEAN" in itt


def should_skip(sidecar: dict) -> bool:
    desc = sidecar.get("SeriesDescription") or ""
    return bool(SKIP_RE.search(desc))


def image_type_pattern(image_type_text: list[str] | None) -> list[str]:
    if not image_type_text:
        return [".*"]
    return [
        "NORM" if token == "NORM" else "MEAN" if token == "MEAN" else ".*"
        for token in image_type_text
    ]


def infer_suffix(desc: str) -> str:
    d = desc.lower()
    if re.search(r"\bt2\b|t2w|tse|space", d):
        return "T2w"
    if re.search(r"\bt1\b|t1w|tfl|mprage|mp2rage", d):
        return "T1w"
    return "T1w"


def assign_runs(group: list[dict]) -> list[tuple[dict, str, str]]:
    """Return (sidecar, rec, run_label) for a same-description primary group."""
    ordered = sorted(group, key=lambda s: s["SeriesNumber"])
    run = 0
    out: list[tuple[dict, str, str]] = []
    for sc in ordered:
        rec = "rec-norm" if is_norm(sc.get("ImageTypeText")) else "rec-orig"
        if rec == "rec-orig":
            run += 1
        if run == 0:
            run = 1
        out.append((sc, rec, f"run-{run:02d}"))
    return out


def build_descriptions(sidecars: list[dict]) -> list[dict]:
    primaries: dict[str, list[dict]] = defaultdict(list)
    means: list[dict] = []

    for sc in sidecars:
        if should_skip(sc):
            continue
        if is_mean(sc):
            means.append(sc)
            continue
        desc = sc.get("SeriesDescription") or ""
        primaries[desc].append(sc)

    descriptions: list[dict] = []

    for desc, group in sorted(primaries.items()):
        suffix = infer_suffix(desc)
        desc_re = re.escape(desc)
        for sc, rec, run in assign_runs(group):
            sn = sc["SeriesNumber"]
            descriptions.append(
                {
                    "id": f"{suffix}_sn{sn}",
                    "datatype": "anat",
                    "suffix": suffix,
                    "custom_entities": f"{run}_{rec}",
                    "criteria": {
                        "SeriesNumber": f"^{sn}$",
                        "SeriesDescription": f"^{desc_re}$",
                        "ImageTypeText": image_type_pattern(sc.get("ImageTypeText")),
                    },
                }
            )

    known_pairs: set[str] = set()
    for sc in means:
        desc = sc.get("SeriesDescription") or ""
        m = MEAN_RE.match(desc)
        suffix = infer_suffix(desc)
        itt = image_type_pattern(sc.get("ImageTypeText"))

        if m:
            a, b = m.group(1), m.group(2)
            pair = f"{a}_{b}_"
            known_pairs.add(pair)
            descriptions.append(
                {
                    "id": f"T1w_mean{a}{b}",
                    "datatype": "anat",
                    "suffix": suffix,
                    "custom_entities": f"acq-mean{a}{b}",
                    "criteria": {
                        "SeriesNumber": r"^10\d+$",
                        "SeriesDescription": f"^MEAN_{a}_{b}_",
                        "ImageTypeText": itt,
                    },
                }
            )
        else:
            descriptions.append(
                {
                    "id": f"T1w_mean_sn{sc['SeriesNumber']}",
                    "datatype": "anat",
                    "suffix": suffix,
                    "custom_entities": "acq-mean",
                    "criteria": {
                        "SeriesNumber": f"^{sc['SeriesNumber']}$",
                        "SeriesDescription": f"^{re.escape(desc)}$",
                        "ImageTypeText": itt,
                    },
                }
            )

    if means and known_pairs:
        lookahead = "|".join(re.escape(p) for p in sorted(known_pairs))
        descriptions.append(
            {
                "id": "T1w_mean_catchall",
                "datatype": "anat",
                "suffix": "T1w",
                "custom_entities": "acq-mean",
                "criteria": {
                    "SeriesNumber": r"^10\d+$",
                    "SeriesDescription": f"^MEAN_(?!{lookahead})",
                    "ImageTypeText": itt,
                },
            }
        )

    return descriptions


def warn_series_infos(sidecars: list[dict], series_info: Path | None) -> None:
    if not series_info or not series_info.is_file():
        return
    by_sn: dict[int, str] = {}
    for line in series_info.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 9 or parts[0] != "DAG":
            continue
        try:
            sn = int(parts[3])
        except ValueError:
            continue
        by_sn[sn] = parts[8].strip()

    for sc in sidecars:
        sn = sc.get("SeriesNumber")
        if sn not in by_sn:
            continue
        dicom_desc = sc.get("SeriesDescription") or ""
        info_desc = by_sn[sn]
        if info_desc and info_desc not in dicom_desc and dicom_desc not in info_desc:
            print(
                f"WARNING: SN {sn} SeriesInfos={info_desc!r} "
                f"!= DICOM={dicom_desc!r} (using DICOM)",
                file=sys.stderr,
            )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("helper_dir", type=Path, help="dcm2bids_helper JSON directory")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument(
        "--series-info",
        type=Path,
        default=None,
        help="Optional SeriesInfos.txt for mismatch warnings only",
    )
    args = parser.parse_args()

    sidecars = load_sidecars(args.helper_dir)
    if args.series_info is None:
        for candidate in (
            args.helper_dir.parent.parent.parent / "SeriesInfos.txt",
            args.helper_dir.parent.parent.parent.parent / "SeriesInfos.txt",
        ):
            if candidate.is_file():
                args.series_info = candidate
                break

    warn_series_infos(sidecars, args.series_info)

    config = {
        "dcm2niixOptions": DCM2NIIX_OPTIONS,
        "search_method": "re",
        "case_sensitive": True,
        "descriptions": build_descriptions(sidecars),
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w") as f:
        json.dump(config, f, indent=4)
        f.write("\n")

    print(f"Wrote {len(config['descriptions'])} descriptions -> {args.output}")


if __name__ == "__main__":
    main()
