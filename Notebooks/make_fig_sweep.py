"""
make_fig_sweep.py -- Fig. 2 of the revised letter (figures/fig_dsp_sweep.png/.pdf).

DSP blocks (top) and LUTs (bottom) against the conv2 weight width, HLS estimate and
out-of-context synthesis, under the default, DSP-bound and fabric-bound flows.
Run from the repository root:  python Notebooks/make_fig_sweep.py
"""
import csv, os
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
try:                                   # inline display in a notebook, silent otherwise
    from IPython.display import Image, display
except ImportError:
    Image = display = None

OUT_DIR = "Results/Binding"   # bind_B.csv and bind_synth_B.csv (run from the repository root)
FIG_DIR = "figures"           # figures are written here
os.makedirs(FIG_DIR, exist_ok=True)

H = {(r["config"], r["bind"]): r for r in csv.DictReader(open(os.path.join(OUT_DIR, "bind_B.csv")))}
S = {(r["config"], r["bind"]): r for r in csv.DictReader(open(os.path.join(OUT_DIR, "bind_synth_B.csv")))}
bits = [8, 7, 6, 5, 4, 3, 2]
cfg = [f"B_W{b}_A8" for b in bits]

def col(table, mode, key):
    return [int(float(table[(c, mode)][key])) for c in cfg]

hls_def, hls_dsp = col(H, "default", "DSP_hls"), col(H, "dsp", "DSP_hls")
syn_def, syn_dsp = col(S, "default", "DSP_built"), col(S, "dsp", "DSP_built")
syn_fab, hls_fab = col(S, "fabric", "DSP_built"), col(H, "fabric", "DSP_hls")
lut = {m: col(S, m, "LUT_built") for m in ("default", "dsp", "fabric")}
assert syn_fab == hls_fab == [0] * len(bits), "fabric flow expected to be 0 everywhere"

# colour roles: one hue per binding mode; built = solid/filled, HLS = dashed/open
C_DEF, C_DSP, C_FAB = "#2a78d6", "#eb6834", "#199e70"     # blue, orange, aqua (CVD-validated)
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e4e3df"
BAND = "#cde2fb"                                          # light tint of the default-flow hue

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Times New Roman", "Liberation Serif", "STIXGeneral", "DejaVu Serif"],
    "font.size": 8, "axes.linewidth": 0.6, "axes.edgecolor": INK2,
    "xtick.color": INK2, "ytick.color": INK2, "axes.labelcolor": INK,
    "xtick.major.width": 0.6, "ytick.major.width": 0.6,
    "xtick.major.size": 2.5, "ytick.major.size": 2.5,
    "pdf.fonttype": 42, "ps.fonttype": 42,
})

def style(ax):
    ax.set_xlim(8.35, 1.65)                    # wide -> narrow, left to right
    ax.set_xticks(bits)
    ax.grid(axis="y", lw=0.4, color=GRID)
    ax.set_axisbelow(True)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.axvspan(4.0, 5.0, color=BAND, alpha=0.75, lw=0, zorder=0)

def dsp_panel(ax, brackets=True, band_label=True, leg_y=0.17, legend=True):
    style(ax)
    ax.plot(bits, syn_def, color=C_DEF, lw=1.6, marker="o", ms=4.4, mec="white", mew=0.6,
            label="default, built", zorder=4)
    ax.plot(bits, hls_def, color=C_DEF, lw=1.0, ls=(0, (3.5, 2)), marker="o", ms=4.2,
            mfc="white", mew=1.0, label="default, HLS", zorder=3)
    ax.plot(bits, syn_dsp, color=C_DSP, lw=1.6, marker="s", ms=4.0, mec="white", mew=0.6,
            label="DSP-bound, built", zorder=4)
    ax.plot(bits, hls_dsp, color=C_DSP, lw=1.0, ls=(0, (3.5, 2)), marker="s", ms=3.8,
            mfc="white", mew=1.0, label="DSP-bound, HLS", zorder=3)
    ax.plot(bits, syn_fab, color=C_FAB, lw=1.4, zorder=2)
    ax.text(7.95, 2.5, "fabric-bound: HLS = built = 0", fontsize=6.5, color=C_FAB,
            va="bottom", fontweight="bold")
    ax.set_ylim(-6, 115)
    ax.set_ylabel("DSP blocks", labelpad=1.5)
    if band_label:
        ax.text(4.5, 113, "threshold\n(default)", fontsize=6, color=INK2,
                ha="center", va="top", linespacing=0.95)
    if brackets:   # estimate error of the default flow, opposite signs either side
        for x, i in ((8, 0), (4, 4)):
            lo, hi = sorted((hls_def[i], syn_def[i]))
            ax.annotate("", xy=(x - 0.18, lo), xytext=(x - 0.18, hi),
                        arrowprops=dict(arrowstyle="<->", lw=0.6, color=INK2,
                                        shrinkA=1, shrinkB=1))
            ax.text(x - 0.26, (lo + hi) / 2, f"{hls_def[i] - syn_def[i]:+d}".replace("-", "\u2212"), fontsize=6.5,
                    color=INK2, ha="left", va="center")
    if legend:
        ax.legend(loc="lower left", bbox_to_anchor=(0.0, leg_y), fontsize=6.3, frameon=False,
                  handlelength=2.4, borderaxespad=0.2, labelspacing=0.25)

def save_show(fig, name):
    png = os.path.join(FIG_DIR, f"{name}.png")
    fig.savefig(png, dpi=300)
    fig.savefig(os.path.join(FIG_DIR, f"{name}.pdf"))
    plt.close(fig)
    if display is not None:
        display(Image(filename=png, width=700))
    print("written", png)

# ---- DSP panel + LUT panel ------------------------------------------------------
fig, (a1, a2) = plt.subplots(2, 1, figsize=(3.5, 2.75), sharex=True, layout="constrained",
                             gridspec_kw=dict(height_ratios=[1.7, 1.0]))
fig.get_layout_engine().set(w_pad=0.02, h_pad=0.02, hspace=0.02)
dsp_panel(a1, brackets=True, legend=False)
style(a2)
for m, c, mk, lab in (("default", C_DEF, "o", "default"), ("dsp", C_DSP, "s", "DSP-bound"),
                      ("fabric", C_FAB, "^", "fabric-bound")):
    a2.plot(bits, [v / 1000 for v in lut[m]], color=c, lw=1.4, marker=mk, ms=3.8,
            mec="white", mew=0.6, label=lab)
a2.set_ylim(4, 14.5)
a2.set_yticks([5, 10])
a2.set_ylabel("LUTs (k), built", labelpad=1.5)
a2.set_xlabel("conv2 weight width (bits), activations 8 bits", labelpad=1.5)
# one legend for both panels: colour = binding mode, line style = built vs HLS estimate
handles = [
    Line2D([], [], color=C_DEF, lw=1.6, marker="o", ms=4.0, mec="white", mew=0.6, label="default"),
    Line2D([], [], color=C_DSP, lw=1.6, marker="s", ms=3.8, mec="white", mew=0.6, label="DSP-bound"),
    Line2D([], [], color=C_FAB, lw=1.6, marker="^", ms=3.8, mec="white", mew=0.6, label="fabric-bound"),
    Line2D([], [], color=INK2, lw=1.4, marker="o", ms=3.8, mec="white", mew=0.6, label="built"),
    Line2D([], [], color=INK2, lw=1.0, ls=(0, (3.5, 2)), marker="o", ms=3.6, mfc="white",
           mew=0.9, label="HLS estimate"),
]
fig.legend(handles=handles, loc="outside upper center", ncol=5, fontsize=6.3, frameon=False,
           handlelength=1.9, handletextpad=0.4, columnspacing=0.9, borderaxespad=0.0)
save_show(fig, "fig_dsp_sweep")          # Fig. 2 of the revised letter

for name, v in [("default built", syn_def), ("default HLS", hls_def),
                ("DSP-bound built", syn_dsp), ("DSP-bound HLS", hls_dsp)]:
    print(f"{name:16s}", dict(zip(bits, v)))
for m in lut:
    print(f"LUT {m:12s}", dict(zip(bits, lut[m])))
