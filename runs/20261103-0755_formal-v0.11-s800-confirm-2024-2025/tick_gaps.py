"""Find intra-week gaps in the monthly tick binaries (records <q d d> = time_msc, bid, ask).

Reports, per month, gaps longer than --min-gap minutes that are NOT the regular weekend close
(Fri >= 20:00 GMT -> Sun/Mon). Daily-break gaps (~21:00-23:00 GMT) up to --break-max minutes
are counted separately. Read-only.
usage: python -I tick_gaps.py <dir> [--min-gap 15] [--break-max 75]
"""
import argparse, glob, json, os
import numpy as np, pandas as pd
ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("--min-gap", type=float, default=15); ap.add_argument("--break-max", type=float, default=75)
a = ap.parse_args()
rec = np.dtype([("msc", "<i8"), ("bid", "<f8"), ("ask", "<f8")])
out = {}; prev = None
for f in sorted(glob.glob(os.path.join(a.dir, "ticks_*.bin"))):
    msc = np.fromfile(f, dtype=rec)["msc"]
    if prev is not None: msc = np.concatenate(([prev], msc))
    prev = int(msc[-1])
    d = np.diff(msc) / 60000.0
    idx = np.nonzero(d > a.min_gap)[0]
    starts = pd.to_datetime(msc[idx], unit="ms"); mins = d[idx]
    weekend = ((starts.dayofweek == 4) & (starts.hour >= 19)) | (starts.dayofweek == 5) | (starts.dayofweek == 6)
    brk = (~weekend) & (starts.hour >= 20) & (starts.hour <= 22) & (mins <= a.break_max)
    other = ~(weekend | brk)
    mon = os.path.basename(f)[6:12]
    out[mon] = {"weekend_or_holiday": int(weekend.sum()), "daily_break": int(brk.sum()),
                "other_gaps": [f"{s:%Y-%m-%d %a %H:%M} {m:.0f}min" for s, m in zip(starts[other], mins[other])]}
tot = sum(len(v["other_gaps"]) for v in out.values())
for m, v in out.items():
    if v["other_gaps"]: print(m, len(v["other_gaps"]), v["other_gaps"][:6])
print("months", len(out), "total other gaps >", a.min_gap, "min:", tot)
json.dump(out, open(os.path.join(a.dir, "gap_report.json"), "w"), indent=1)
