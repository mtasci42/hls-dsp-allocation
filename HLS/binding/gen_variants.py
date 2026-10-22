#!/usr/bin/env python3
"""
gen_variants.py -- synthesis-only design variants for the ESL revision.

Standard library only. Run from the HLS root (repository: HLS/):

    python binding/gen_variants.py sweep   # weight-width sweep: B_W8_A8 ... B_W2_A8
    python binding/gen_variants.py arch    # wider network: C_W8_A8, C_W4_A8
    python binding/gen_variants.py check   # per-ROM conv2 weight widths of all variants

Each variant is a new folder next to W_int8_A8 with cnn.cpp and cnn.h copied
unchanged from W_int8_A8 and a regenerated weights.h. Nothing existing is modified.

Group B (sweep): conv2 weights of W_int8_A8 are re-quantized to b bits by an
arithmetic right shift with rounding, q = clip(round(w / 2^(8-b))), clipped to
[-2^(b-1), 2^(b-1)-1]. ACC2_W follows the rule A1_BITS + b + ceil(log2(C2_K*C1_COUT)),
which reproduces ACC2_W = 19 of W_int4_A8. Everything else (conv1, requant constants,
dense) is kept from W_int8_A8, so the only change between sweep points is the conv2
weight width. These designs are for resource characterisation only: no retraining,
no accuracy claim.

Group C (arch): conv1 widened to 32 output channels and conv2 to 64, so conv2 has
5*32 = 160 parallel products per iteration instead of 80. Weights and requant
constants are resampled (fixed seed) from the W_int8_A8 arrays; the 4-bit variant
is derived from the same 8-bit draw with the same shift rule. Synthesis only.
"""
import math
import os
import random
import re
import shutil
import sys

# Run from the HLS root (the folder holding W_int8_A8/). In the repository the
# script lives in HLS/binding/, so call it as: python binding/gen_variants.py sweep
ROOT = os.getcwd()
BASE = os.path.join(ROOT, "W_int8_A8")
SEED = 2026

ARR_RE = re.compile(
    r"static\s+const\s+(\w+)\s+(\w+)((?:\[\d+\])+)\s*=\s*(\{.*?\});", re.S)
DEF_RE = re.compile(r"^#define\s+(\w+)\s+(-?\d+)\s*$", re.M)


# ---------------------------------------------------------------- parsing ---
def read_weights(path):
    src = open(path, encoding="utf-8").read()
    defs = {k: int(v) for k, v in DEF_RE.findall(src)}
    arrs = {}
    for ctype, name, dims, body in ARR_RE.findall(src):
        shape = [int(d) for d in re.findall(r"\d+", dims)]
        vals = [int(v) for v in re.findall(r"-?\d+", body)]
        n = 1
        for d in shape:
            n *= d
        if len(vals) != n:
            raise ValueError(f"{name}: expected {n} values, got {len(vals)}")
        arrs[name] = (ctype, shape, vals)
    return src, defs, arrs


def fmt_array(ctype, name, shape, vals):
    def rec(level, off):
        if level == len(shape) - 1:
            return "{" + ",".join(str(v) for v in vals[off:off + shape[-1]]) + "}"
        step = 1
        for d in shape[level + 1:]:
            step *= d
        parts = [rec(level + 1, off + i * step) for i in range(shape[level])]
        sep = ",\n" if level == len(shape) - 2 else ","
        return "{" + sep.join(parts) + "}"
    dims = "".join(f"[{d}]" for d in shape)
    return f"static const {ctype} {name}{dims} = {rec(0, 0)};"


def write_weights(path, comment, defs, arrs, order):
    out = ["#ifndef WEIGHTS_H", "#define WEIGHTS_H", "#include <stdint.h>", "",
           f"// {comment}", ""]
    for k, v in defs.items():
        out.append(f"#define {k} {v}")
    out.append("")
    for name in order:
        ctype, shape, vals = arrs[name]
        out.append(fmt_array(ctype, name, shape, vals))
        out.append("")
    out.append("#endif")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


# ------------------------------------------------------------- utilities ---
def requant(vals, b):
    if b >= 8:
        return list(vals)
    sh = 8 - b
    lo, hi = -(1 << (b - 1)), (1 << (b - 1)) - 1
    out = []
    for w in vals:
        q = (w + (1 << (sh - 1))) >> sh       # round half up, arithmetic shift
        out.append(min(hi, max(lo, q)))
    return out


def acc2_rule(a1_bits, b, c2_k, c1_cout):
    return a1_bits + b + math.ceil(math.log2(c2_k * c1_cout))


def min_bits(lo, hi):
    b = 1
    while not (-(1 << (b - 1)) <= lo and hi <= (1 << (b - 1)) - 1):
        b += 1
    return b


def rom_widths(arrs, defs):
    _, shape, vals = arrs["W2"]
    K, CI, CO = shape
    hist = {}
    for k in range(K):
        for ci in range(CI):
            col = [vals[(k * CI + ci) * CO + co] for co in range(CO)]
            w = min_bits(min(col), max(col))
            hist[w] = hist.get(w, 0) + 1
    return dict(sorted(hist.items()))


def make_dir(name):
    d = os.path.join(ROOT, name)
    if os.path.exists(d):
        print(f"  {name}: exists, weights.h will be overwritten (bind_* projects kept)")
    os.makedirs(d, exist_ok=True)
    for f in ("cnn.cpp", "cnn.h"):          # per-config copy, else the shared HLS/ source
        src = os.path.join(BASE, f) if os.path.isfile(os.path.join(BASE, f)) else os.path.join(ROOT, f)
        shutil.copyfile(src, os.path.join(d, f))
    return d


ORDER = ["W1", "M01", "B1", "W2", "M02", "B2", "WD", "M0D", "BD"]


# ---------------------------------------------------------------- Group B ---
def sweep():
    _, defs, arrs = read_weights(os.path.join(BASE, "weights.h"))
    rule8 = acc2_rule(defs["A1_BITS"], 8, defs["C2_K"], defs["C1_COUT"])
    if rule8 != defs["ACC2_W"]:
        print(f"WARNING: base ACC2_W={defs['ACC2_W']} but rule gives {rule8} at b=8")
    for b in range(8, 1, -1):
        name = f"B_W{b}_A8"
        d = make_dir(name)
        nd = dict(defs)
        nd["MODE_C2"] = b
        nd["ACC2_W"] = acc2_rule(defs["A1_BITS"], b, defs["C2_K"], defs["C1_COUT"])
        na = dict(arrs)
        ct, sh, v = arrs["W2"]
        na["W2"] = (ct, sh, requant(v, b))
        write_weights(os.path.join(d, "weights.h"),
                      f"config: {name}  Group B sweep, conv2 weights = W_int8_A8 >> {8-b} "
                      f"(rounded, clipped to {b} bits); synthesis only, no accuracy claim",
                      nd, na, ORDER)
        q = na["W2"][2]
        print(f"  {name}: ACC2_W={nd['ACC2_W']}  W2 range [{min(q)},{max(q)}]  "
              f"ROM widths {rom_widths(na, nd)}")


# ---------------------------------------------------------------- Group C ---
def arch():
    _, defs, arrs = read_weights(os.path.join(BASE, "weights.h"))
    rng = random.Random(SEED)
    C1, C2 = 32, 64
    pool = lambda n: arrs[n][2]

    def draw(name, n):
        p = pool(name)
        return [rng.choice(p) for _ in range(n)]

    K1, K2, NC = defs["C1_K"], defs["C2_K"], defs["N_CLASS"]
    base = {
        "W1":  ("int8_t",  [K1, 1, C1], draw("W1", K1 * C1)),
        "M01": ("int32_t", [C1],        draw("M01", C1)),
        "B1":  ("int32_t", [C1],        draw("B1", C1)),
        "W2":  ("int8_t",  [K2, C1, C2], draw("W2", K2 * C1 * C2)),
        "M02": ("int32_t", [C2],        draw("M02", C2)),
        "B2":  ("int32_t", [C2],        draw("B2", C2)),
        "WD":  ("int8_t",  [C2, NC],    draw("WD", C2 * NC)),
        "M0D": arrs["M0D"],
        "BD":  arrs["BD"],
    }
    for b in (8, 4):
        name = f"C_W{b}_A8"
        d = make_dir(name)
        nd = dict(defs)
        nd["C1_COUT"], nd["C2_COUT"], nd["MODE_C2"] = C1, C2, b
        nd["ACC2_W"] = acc2_rule(defs["A1_BITS"], b, K2, C1)
        nd["DACC_W"] = defs["DACC_W"] + 1      # twice as many dense inputs
        nd["DMUL_W"] = defs["DMUL_W"] + 1
        na = dict(base)
        ct, sh, v = base["W2"]
        na["W2"] = (ct, sh, requant(v, b))
        write_weights(os.path.join(d, "weights.h"),
                      f"config: {name}  Group C wider network (C1_COUT={C1}, C2_COUT={C2}), "
                      f"weights resampled from W_int8_A8 (seed {SEED}); synthesis only",
                      nd, na, ORDER)
        q = na["W2"][2]
        print(f"  {name}: conv2 products/iter={K2*C1}  ACC2_W={nd['ACC2_W']}  "
              f"W2 range [{min(q)},{max(q)}]  ROM widths {rom_widths(na, nd)}")


def check():
    for d in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, d, "weights.h")
        if os.path.isfile(p):
            try:
                _, defs, arrs = read_weights(p)
                print(f"  {d:14s} ACC2_W={defs.get('ACC2_W')}  ROM widths {rom_widths(arrs, defs)}")
            except Exception as e:
                print(f"  {d:14s} parse error: {e}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if not os.path.isfile(os.path.join(BASE, "weights.h")) and cmd in ("sweep", "arch"):
        sys.exit(f"base not found: {BASE}\\weights.h (run from the HLS root)")
    {"sweep": sweep, "arch": arch, "check": check}.get(
        cmd, lambda: print(__doc__))()
