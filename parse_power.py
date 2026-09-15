#!/usr/bin/env python3
"""
parse_power.py -- reproduce the measured power results of

    DSP Allocation in Quantized CNN Accelerators:
    HLS Estimates Against Synthesized Netlists

from the raw FNIRSI FNB58 logs in results/power/.

The analyser writes a four-column CSV (Time, Voltage, Current, Power) at
10 samples/s, preceded by comment lines starting with '#'.

Naming convention in results/power/:

    A0.csv                  empty processing-system-only bitstream (the floor)
    B<r>_<config>.csv       accelerator loaded but idle,      repeat r = 0,1,2
    C<r>_<config>.csv       continuous inference,             repeat r = 0,1,2

with <config> in {w8a8, w4a8, a8a4, a4a4, ternaryA8}.

Reported quantities
-------------------
    P_act = mean(P_C) - mean(P_B)        per repeat, then mean +- sd over repeats
    E     = P_act * t_win                t_win = 1.837 ms (streamed window)
    P_B - P_A                            static and clock-network cost

Two uncertainties are distinguished: the within-window standard error, obtained
from the means of consecutive 10 s blocks, and the between-repeat standard
deviation across the three A/B/C sequences.

Usage
-----
    python parse_power.py [--dir results/power] [--twin 1.837]
"""

import argparse
import glob
import math
import os
import re
import statistics as st

CONFIGS = ["w8a8", "w4a8", "a8a4", "a4a4", "ternaryA8"]
LABEL = {"w8a8": "W8A8", "w4a8": "W4A8", "a8a4": "W8A4",
         "a4a4": "W4A4", "ternaryA8": "TerA8"}
SPS = 10           # analyser sample rate, samples per second
BLOCK_S = 10       # block length for the within-window standard error


def load(path):
    """Return the power column of one FNB58 log, in watts."""
    out = []
    with open(path, newline="") as fh:
        for line in fh:
            if line.startswith("#") or line.startswith("Time"):
                continue
            f = line.strip().split(",")
            if len(f) >= 4 and f[3]:
                out.append(float(f[3]))
    if not out:
        raise ValueError(f"no samples parsed from {path}")
    return out


def block_sem(p, block_s=BLOCK_S, sps=SPS):
    """Standard error of the mean from non-overlapping block means, in mW."""
    n = len(p) // (block_s * sps)
    if n < 2:
        return float("nan")
    means = [st.mean(p[i * block_s * sps:(i + 1) * block_s * sps]) for i in range(n)]
    return st.stdev(means) / math.sqrt(n) * 1000.0


def welch(x, y):
    """Welch t statistic and degrees of freedom for two small samples."""
    if len(x) < 2 or len(y) < 2:
        return float("nan"), float("nan")
    vx, vy = st.variance(x) / len(x), st.variance(y) / len(y)
    se = math.sqrt(vx + vy)
    if se == 0:
        return float("nan"), float("nan")
    t = (st.mean(x) - st.mean(y)) / se
    df = (vx + vy) ** 2 / (vx ** 2 / (len(x) - 1) + vy ** 2 / (len(y) - 1))
    return t, df


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(__file__), "power"))
    ap.add_argument("--twin", type=float, default=1.837,
                    help="streamed window time in ms (default 1.837)")
    args = ap.parse_args()

    logs = {}
    for path in glob.glob(os.path.join(args.dir, "*.csv")):
        name = os.path.basename(path)
        if name.upper().startswith("A0"):
            logs[("A", 0, None)] = load(path)
            continue
        m = re.match(r"([BCbc])([0-9])_(.+)\.csv$", name)
        if m:
            logs[(m.group(1).upper(), int(m.group(2)), m.group(3))] = load(path)

    if ("A", 0, None) not in logs:
        raise SystemExit(f"A0.csv not found in {args.dir}")
    p_a = st.mean(logs[("A", 0, None)])

    print(f"floor  P_A = {p_a:.4f} W   "
          f"({len(logs[('A', 0, None)])} samples, "
          f"SEM {block_sem(logs[('A', 0, None)]):.1f} mW)\n")

    head = (f"{'config':<8}{'P_B (W)':>9}{'P_C (W)':>9}"
            f"{'P_B-P_A (mW)':>15}{'P_act (mW)':>22}{'E (mJ)':>9}")
    print(head)
    print("-" * len(head))

    act = {}
    for cfg in CONFIGS:
        d, b_abs, c_abs, sems = [], [], [], []
        for r in range(3):
            kb, kc = ("B", r, cfg), ("C", r, cfg)
            if kb not in logs or kc not in logs:
                continue
            mb, mc = st.mean(logs[kb]), st.mean(logs[kc])
            d.append((mc - mb) * 1000.0)
            b_abs.append(mb)
            c_abs.append(mc)
            sems += [block_sem(logs[kb]), block_sem(logs[kc])]
        if not d:
            print(f"{LABEL[cfg]:<8}  (no logs)")
            continue
        act[cfg] = d
        sd = st.stdev(d) if len(d) > 1 else 0.0
        print(f"{LABEL[cfg]:<8}{st.mean(b_abs):9.3f}{st.mean(c_abs):9.3f}"
              f"{(st.mean(b_abs) - p_a) * 1000:15.1f}"
              f"{st.mean(d):16.1f} +- {sd:4.1f}"
              f"{st.mean(d) * args.twin / 1000:9.3f}")

    sems = [block_sem(v) for v in logs.values()]
    sems = [s for s in sems if not math.isnan(s)]
    if sems:
        print(f"\nwithin-window SEM across all logs: "
              f"{min(sems):.1f} to {max(sems):.1f} mW")

    print("\nternary against the multiply-based configurations (Welch, n = 3):")
    for cfg in ["w4a8", "w8a8", "a8a4", "a4a4"]:
        if cfg in act and "ternaryA8" in act:
            t, df = welch(act["ternaryA8"], act[cfg])
            diff = st.mean(act["ternaryA8"]) - st.mean(act[cfg])
            print(f"  TerA8 - {LABEL[cfg]:<6} {diff:6.1f} mW   "
                  f"t = {t:5.2f}   df = {df:.1f}")

    print("\nPer-repeat P_act (mW), for inspection:")
    for cfg in CONFIGS:
        if cfg in act:
            print(f"  {LABEL[cfg]:<8}" + "  ".join(f"{v:7.1f}" for v in act[cfg]))


if __name__ == "__main__":
    main()
