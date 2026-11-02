"""Build shareable OHLC bars from the monthly tick binaries (records <q d d> = time_msc, bid, ask).

Output parquet (zstd), one row per bar, time = bar open in GMT+0 (same clock as the MT5 custom
symbol XAUUSD_GD and the deal CSVs of the formal runs):
  time, bid_o, bid_h, bid_l, bid_c, ask_o, ask_h, ask_l, ask_c, ticks, sp_min, sp_mean, sp_max
MT5 charts and the tester's bars are bid-based; ask columns are for showing BUY fills / SL on the ask side.

usage: python -I export_ohlc.py <tick_dir> <out_dir> --from 202201 --to 202512 --tf 1 5
"""
import argparse, glob, os, hashlib, json
import numpy as np, pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument("ticks"); ap.add_argument("out")
ap.add_argument("--from", dest="m0", default="202201"); ap.add_argument("--to", dest="m1", default="202512")
ap.add_argument("--tf", type=int, nargs="+", default=[1, 5])
a = ap.parse_args()
rec = np.dtype([("msc", "<i8"), ("bid", "<f8"), ("ask", "<f8")])
os.makedirs(a.out, exist_ok=True)
parts = {tf: [] for tf in a.tf}
for f in sorted(glob.glob(os.path.join(a.ticks, "ticks_*.bin"))):
    mon = os.path.basename(f)[6:12]
    if not (a.m0 <= mon <= a.m1): continue
    t = np.fromfile(f, dtype=rec)
    df = pd.DataFrame({"bid": t["bid"], "ask": t["ask"]}, index=pd.to_datetime(t["msc"], unit="ms"))
    df["sp"] = df["ask"] - df["bid"]
    for tf in a.tf:
        g = df.resample(f"{tf}min", label="left", closed="left")
        o = pd.concat({"bid_o": g["bid"].first(), "bid_h": g["bid"].max(), "bid_l": g["bid"].min(), "bid_c": g["bid"].last(),
                       "ask_o": g["ask"].first(), "ask_h": g["ask"].max(), "ask_l": g["ask"].min(), "ask_c": g["ask"].last(),
                       "ticks": g["bid"].count(), "sp_min": g["sp"].min(), "sp_mean": g["sp"].mean(), "sp_max": g["sp"].max()}, axis=1)
        o = o[o["ticks"] > 0]
        parts[tf].append(o)
    print(mon, len(t), flush=True)
meta = {"source": "XAUUSD_GMT+0_2020~2026.csv (provider not identified)", "timezone": "GMT+0", "months": [a.m0, a.m1], "files": {}}
for tf, ps in parts.items():
    o = pd.concat(ps); o.index.name = "time"
    for c in o.columns:
        if c != "ticks": o[c] = o[c].round(3)
    p = os.path.join(a.out, f"xauusd_gd_m{tf}_{a.m0}_{a.m1}.parquet")
    o.reset_index().to_parquet(p, compression="zstd", index=False)
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    meta["files"][os.path.basename(p)] = {"rows": len(o), "bytes": os.path.getsize(p), "sha256": h, "first": str(o.index[0]), "last": str(o.index[-1])}
json.dump(meta, open(os.path.join(a.out, "ohlc_meta.json"), "w"), indent=1)
print(json.dumps(meta, indent=1))
