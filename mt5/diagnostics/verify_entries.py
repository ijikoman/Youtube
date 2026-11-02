"""Cross-check ResearchPullback v0.10 tester output against its written spec.

usage: python -I verify_entries.py <bardump.csv> <deals.csv> <agent.log> <report.htm> [--from HH:MM:SS] [--to HH:MM:SS]
        [--stop-atr 1.5] [--rr 2.0] [--max-spread 1000] [--tick 0.001] [--fast 20] [--slow 50] [--atr 14]

Read-only diagnostic. It does not change the EA or its rules; it reports mismatches.
"""
import argparse, csv, re, html
from datetime import datetime

ap = argparse.ArgumentParser()
ap.add_argument("bardump"); ap.add_argument("deals"); ap.add_argument("agentlog"); ap.add_argument("report")
ap.add_argument("--from", dest="tfrom", default=None, help="agent-log wall-clock start of the run section (HH:MM:SS)")
ap.add_argument("--to", dest="tto", default=None)
ap.add_argument("--stop-atr", type=float, default=1.5); ap.add_argument("--rr", type=float, default=2.0)
ap.add_argument("--max-spread", type=int, default=1000); ap.add_argument("--tick", type=float, default=0.001)
ap.add_argument("--fast", type=int, default=20); ap.add_argument("--slow", type=int, default=50); ap.add_argument("--atr", type=int, default=14)
a = ap.parse_args()
T = lambda s: datetime.strptime(s, "%Y.%m.%d %H:%M:%S")
rnd = lambda x: round(round(x / a.tick) * a.tick, 3)
issues = []

# ---- bars + independent indicator recomputation -------------------------------------------
rows = list(csv.DictReader(open(a.bardump, encoding="utf-8-sig")))
for r in rows:
    for k in ("open", "high", "low", "close", "ema_fast", "ema_slow", "atr"):
        r[k] = float(r[k])
closes = [r["close"] for r in rows]
def ema(n):
    out, k = [], 2 / (n + 1)
    for i, c in enumerate(closes):
        out.append(c if i == 0 else out[-1] + k * (c - out[-1]))
    return out
ef, es = ema(a.fast), ema(a.slow)
tr = [rows[0]["high"] - rows[0]["low"]] + [max(r["high"], p["close"]) - min(r["low"], p["close"]) for p, r in zip(rows, rows[1:])]
atr = [None] * len(rows)
for i in range(a.atr - 1, len(rows)):
    atr[i] = sum(tr[i - a.atr + 1:i + 1]) / a.atr
live = [i for i, r in enumerate(rows) if r["phase"] == "live"]
d_ema = max(max(abs(ef[i] - rows[i]["ema_fast"]), abs(es[i] - rows[i]["ema_slow"])) for i in live)
d_atr = max(abs(atr[i] - rows[i]["atr"]) for i in live)
print(f"[indicators] live bars={len(live)}  max|EMA recalcs-MT5|={d_ema:.6f}  max|ATR(SMA TR) recalc-MT5|={d_atr:.6f}")
if d_ema > 0.01 or d_atr > 0.01:
    issues.append("indicator recomputation differs from MT5 values")

# ---- orders from agent log ------------------------------------------------------------------
pat = re.compile(r"\t(\d\d:\d\d:\d\d)\.\d+\tResearchPullback \(.*?\)\t(\S+ \S+)\s+CTrade::OrderSend: market (buy|sell) ([\d.]+) \S+ sl: ([\d.]+) tp: ([\d.]+) \[(.+?)\]")
orders = []
for line in open(a.agentlog, encoding="utf-16"):
    m = pat.search(line)
    if not m: continue
    wall = m.group(1)
    if (a.tfrom and wall < a.tfrom) or (a.tto and wall > a.tto): continue
    res = m.group(7)
    orders.append(dict(time=T(m.group(2)), side=m.group(3), lots=float(m.group(4)), sl=float(m.group(5)), tp=float(m.group(6)),
                       done=float(res.split()[-1]) if res.startswith("done at") else None, result=res))
fails = [l for l in open(a.agentlog, encoding="utf-16") if "Order failure" in l and (not a.tfrom or l.split("\t")[2][:8] >= a.tfrom) and (not a.tto or l.split("\t")[2][:8] <= a.tto)]
print(f"[orders] OrderSend lines={len(orders)}  'Order failure' lines={len(fails)}")

# ---- deals ----------------------------------------------------------------------------------
deals = list(csv.DictReader(open(a.deals, encoding="utf-8-sig")))
pos = {}
for d in deals:
    p = pos.setdefault(d["position"], {})
    p["in" if d["entry"] == "0" else "out"] = d
intervals = sorted((T(p["in"]["time_server"]), T(p["out"]["time_server"]) if "out" in p else datetime.max) for p in pos.values() if "in" in p)
net_csv = sum(float(d["profit"]) + float(d["commission"]) + float(d["swap"]) + float(d["fee"]) for d in deals)
costs = sum(float(d["commission"]) + float(d["swap"]) + float(d["fee"]) for d in deals)
print(f"[deals] positions={len(pos)}  open-at-end={sum('out' not in p for p in pos.values())}  CSV net(profit+comm+swap+fee)={net_csv:.2f}  of which costs={costs:.2f}")

# ---- per-entry spec check -------------------------------------------------------------------
by_first = {r["first_tick_time"]: i for i, r in enumerate(rows) if r["phase"] == "live"}
ok = 0
for o in orders:
    i = by_first.get(o["time"].strftime("%Y.%m.%d %H:%M:%S"))
    tag = f"{o['time']} {o['side']}"
    if i is None:
        issues.append(f"{tag}: no bar whose next-bar first tick == order time (not at first tick of new bar?)"); continue
    b = rows[i]; buy = o["side"] == "buy"
    sig = (b["ema_fast"] > b["ema_slow"] and b["low"] <= b["ema_fast"] and b["close"] > b["ema_fast"] and b["close"] > b["open"]) if buy else \
          (b["ema_fast"] < b["ema_slow"] and b["high"] >= b["ema_fast"] and b["close"] < b["ema_fast"] and b["close"] < b["open"])
    entry = float(b["first_ask"] if buy else b["first_bid"])
    dist = b["atr"] * a.stop_atr
    exp_sl = rnd(entry - dist if buy else entry + dist); exp_tp = rnd(entry + dist * a.rr if buy else entry - dist * a.rr)
    errs = []
    if not sig: errs.append("signal conditions NOT met on prior closed bar")
    if o["done"] is None:
        if not sig: issues.append(f"{tag}: rejected ({o['result']}) and signal NOT met")
        else: print(f"[rejected] {tag}: {o['result']} (signal valid; no same-bar retry expected)")
        continue
    if abs(o["done"] - entry) > a.tick / 2: errs.append(f"fill {o['done']} != first-tick {'ask' if buy else 'bid'} {entry}")
    if abs(o["sl"] - exp_sl) > a.tick / 2: errs.append(f"SL {o['sl']} != expected {exp_sl}")
    if abs(o["tp"] - exp_tp) > a.tick / 2: errs.append(f"TP {o['tp']} != expected {exp_tp}")
    if errs: issues.append(f"{tag}: " + "; ".join(errs))
    else: ok += 1
print(f"[entries] spec-consistent {ok}/{len(orders)}")

# ---- missed signals -------------------------------------------------------------------------
order_times = {o["time"] for o in orders}
missed, blocked_pos, blocked_spread, ambiguous = [], 0, 0, []
for i in live:
    b = rows[i]
    if not b["first_tick_time"]: continue
    t = T(b["first_tick_time"])
    buy = b["ema_fast"] > b["ema_slow"] and b["low"] <= b["ema_fast"] and b["close"] > b["ema_fast"] and b["close"] > b["open"]
    sell = b["ema_fast"] < b["ema_slow"] and b["high"] >= b["ema_fast"] and b["close"] < b["ema_fast"] and b["close"] < b["open"]
    if not (buy or sell) or t in order_times: continue
    if any(s <= t < e for s, e in intervals): blocked_pos += 1; continue
    if any(e == t for s, e in intervals): ambiguous.append(str(t)); continue
    if round((float(b["first_ask"]) - float(b["first_bid"])) / a.tick) > a.max_spread: blocked_spread += 1; continue
    missed.append(str(t))
print(f"[signals not traded] blocked by open position={blocked_pos}  by spread={blocked_spread}  same-second close (ambiguous)={len(ambiguous)}  UNEXPLAINED={len(missed)}")
for m in missed: issues.append(f"signal at {m} not traded and not explained")

# ---- exits ----------------------------------------------------------------------------------
oi = {o["time"]: o for o in orders if o["done"] is not None}
kinds = {"tp": 0, "sl": 0, "other": 0}; slip = []
for p in pos.values():
    if "out" not in p: continue
    o = oi.get(T(p["in"]["time_server"]))
    if not o: continue
    px = float(p["out"]["price"])
    if abs(px - o["tp"]) <= a.tick / 2: kinds["tp"] += 1
    elif abs(px - o["sl"]) <= a.tick / 2: kinds["sl"] += 1
    else:
        kinds["other"] += 1
        slip.append(f"{p['out']['time_server']} out {px} (sl {o['sl']} tp {o['tp']})")
print(f"[exits, exact price match] at TP={kinds['tp']}  at SL={kinds['sl']}  other price={kinds['other']} (real-tick fills cross the level)")

# ---- report reconciliation ------------------------------------------------------------------
raw = open(a.report, "rb").read()
txt = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", "replace")
cells = [html.unescape(re.sub("<[^>]+>", "", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", txt, re.S)]
trows = [[html.unescape(re.sub("<[^>]+>", "", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)] for r in re.findall(r"<tr[^>]*>(.*?)</tr>", txt, re.S)]
rdeals = {c[1]: c for c in trows if len(c) >= 13 and re.match(r"\d{4}\.\d\d\.\d\d", c[0]) and c[3] in ("buy", "sell")}
reasons, dev = {}, {"sl": [], "tp": []}
for c in rdeals.values():
    if c[4] != "out": continue
    p = c[12].split(); reasons[p[0]] = reasons.get(p[0], 0) + 1
    if len(p) == 2 and p[0] in dev: dev[p[0]].append(abs(float(c[6]) - float(p[1])))
print(f"[exits, report comment] {reasons}  max|fill-level| SL={max(dev['sl'], default=0):.3f} TP={max(dev['tp'], default=0):.3f}")
csv_ids = {d["deal"] for d in deals}
only_rep = [k for k in rdeals if k not in csv_ids]
pm = [d["deal"] for d in deals if d["deal"] in rdeals and abs(float(rdeals[d["deal"]][10].replace(" ", "")) - float(d["profit"])) > 0.005]
print(f"[deal match] CSV={len(deals)} report={len(rdeals)} profit mismatches={pm} report-only={[(k, rdeals[k][12], rdeals[k][10]) for k in only_rep]}")
def after(label):
    for j, c in enumerate(cells):
        if c.startswith(label):
            for v in cells[j + 1:j + 3]:
                if v: return v
    return None
for lab in ("総損益", "Total Net Profit", "証拠金最大ドローダウン", "Equity Drawdown Maximal", "残高最大ドローダウン", "Balance Drawdown Maximal",
            "取引数", "Total Trades", "プロフィットファクター", "Profit Factor", "ヒストリー品質", "History Quality", "初期証拠金", "Initial Deposit"):
    v = after(lab)
    if v: print(f"[report] {lab}: {v}")
npv = after("総損益") or after("Total Net Profit")
if npv:
    rep = float(npv.replace(" ", "").replace(",", ""))
    print(f"[reconcile] report net={rep:.2f}  CSV net={net_csv:.2f}  diff={rep - net_csv:.2f}")
    explained = sum(float(rdeals[k][10].replace(" ", "")) for k in only_rep)
    print(f"[reconcile] diff explained by report-only deals: {explained:.2f}")
    if abs(rep - net_csv - explained) > 0.005: issues.append("report net profit != CSV net (+report-only deals)")
    if only_rep: issues.append(f"CSV export misses report-only deals {only_rep} (e.g. 'end of test' close, magic=0) - export issue, not trading logic")

print("\nISSUES:" if issues else "\nISSUES: none")
for s in issues: print(" -", s)
