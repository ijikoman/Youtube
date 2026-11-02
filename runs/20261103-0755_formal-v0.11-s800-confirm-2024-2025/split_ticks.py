"""Split the raw GMT+0 XAUUSD tick CSV into monthly binary files for MT5 custom-symbol import.

CSV line format: "YYYY.MM.DD HH:MM:SS.mmm,bid,ask" (no header).
Output per month: <out>/ticks_YYYYMM.bin, records of little-endian <q d d> = (time_msc, bid, ask), 24 bytes.
Also writes <out>/split_report.json with per-month counts, first/last tick, non-monotonic and
invalid-row counts, max gap, and the SHA256 of each output file.

usage: python -I split_ticks.py <csv> <outdir> --from 2021-11-01 --to 2026-01-01
Read-only on the CSV. Does not change any trading rule.
"""
import argparse, hashlib, json, os, sys, time
import numpy as np
import pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument("csv"); ap.add_argument("out")
ap.add_argument("--from", dest="t0", required=True); ap.add_argument("--to", dest="t1", required=True)
ap.add_argument("--chunk", type=int, default=5_000_000)
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
t0 = int(pd.Timestamp(a.t0).value // 1_000_000); t1 = int(pd.Timestamp(a.t1).value // 1_000_000)  # .value is always ns
rec = np.dtype([("msc", "<i8"), ("bid", "<f8"), ("ask", "<f8")])
stats, handles = {}, {}
last_msc = None; bad = 0; nonmono = 0; started = time.time(); rows = 0

for chunk in pd.read_csv(a.csv, header=None, names=["ts", "bid", "ask"], dtype={"ts": str}, chunksize=a.chunk, engine="c"):
    rows += len(chunk)
    ts = pd.to_datetime(chunk["ts"], format="%Y.%m.%d %H:%M:%S.%f", errors="coerce")
    ok = ts.notna() & chunk["bid"].notna() & chunk["ask"].notna() & (chunk["bid"] > 0) & (chunk["ask"] >= chunk["bid"])
    bad += int((~ok).sum())
    msc = ts[ok].dt.as_unit("ms").astype("int64").to_numpy()  # explicit unit: pandas>=3 may infer us/ms resolution
    bid = chunk["bid"][ok].to_numpy(); ask = chunk["ask"][ok].to_numpy()
    if len(msc) == 0: continue
    if msc[-1] < t0: continue
    if msc[0] >= t1: break
    m = (msc >= t0) & (msc < t1)
    msc, bid, ask = msc[m], bid[m], ask[m]
    if len(msc) == 0: continue
    seq = np.concatenate(([last_msc], msc)) if last_msc is not None else msc
    nonmono += int((np.diff(seq) < 0).sum())
    last_msc = int(msc[-1])
    months = pd.to_datetime(msc, unit="ms").strftime("%Y%m").to_numpy()
    for mon in np.unique(months):
        sel = months == mon
        arr = np.empty(int(sel.sum()), dtype=rec); arr["msc"] = msc[sel]; arr["bid"] = bid[sel]; arr["ask"] = ask[sel]
        if mon not in handles: handles[mon] = open(os.path.join(a.out, f"ticks_{mon}.bin"), "wb")
        handles[mon].write(arr.tobytes())
        s = stats.setdefault(mon, {"ticks": 0, "first": int(arr["msc"][0]), "last": 0, "max_gap_ms": 0, "prev": None, "sp_sum": 0.0})
        g = np.diff(np.concatenate(([s["prev"]], arr["msc"]))) if s["prev"] is not None else np.diff(arr["msc"])
        if len(g): s["max_gap_ms"] = max(s["max_gap_ms"], int(g.max()))
        s["prev"] = int(arr["msc"][-1]); s["last"] = int(arr["msc"][-1]); s["ticks"] += len(arr)
        s["sp_sum"] += float((arr["ask"] - arr["bid"]).sum())
    print(f"rows={rows:,} up_to={pd.to_datetime(last_msc, unit='ms')} elapsed={time.time()-started:.0f}s", flush=True)

for h in handles.values(): h.close()
report = {"csv": os.path.basename(a.csv), "csv_bytes": os.path.getsize(a.csv), "from": a.t0, "to": a.t1, "rows_read": rows,
          "invalid_rows_skipped_all_rows_read": bad, "non_monotonic_steps": nonmono, "months": {}}
for mon, s in sorted(stats.items()):
    p = os.path.join(a.out, f"ticks_{mon}.bin"); h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 24), b""): h.update(b)
    report["months"][mon] = {"ticks": s["ticks"], "first": str(pd.to_datetime(s["first"], unit="ms")), "last": str(pd.to_datetime(s["last"], unit="ms")),
                             "max_gap_min": round(s["max_gap_ms"] / 60000, 1), "mean_spread": round(s["sp_sum"] / s["ticks"], 4), "sha256": h.hexdigest()}
json.dump(report, open(os.path.join(a.out, "split_report.json"), "w"), indent=1)
print("done", json.dumps({k: v for k, v in report.items() if k != "months"}))
