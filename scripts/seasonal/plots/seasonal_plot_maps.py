#!/usr/bin/env python3
"""
Minimal placeholder for seasonal map plotting.
Produces a simple text artifact and a PNG placeholder if matplotlib is present.
"""

import argparse
import os

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MATPLOTLIB = True
except Exception:
    HAS_MATPLOTLIB = False


def parse_args():
    parser = argparse.ArgumentParser(description="EVS seasonal plotting starter")
    parser.add_argument("--run", required=True, choices=["det", "ens"])
    parser.add_argument("--cycle", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--outdir", required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    os.makedirs(args.outdir, exist_ok=True)

    summary = os.path.join(args.outdir, f"seasonal_plot_{args.run}_{args.cycle}.txt")
    with open(summary, "w", encoding="utf-8") as fh:
        fh.write(f"component=seasonal\n")
        fh.write(f"run={args.run}\n")
        fh.write(f"cycle={args.cycle}\n")
        fh.write("status=placeholder\n")

    if HAS_MATPLOTLIB:
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.text(0.5, 0.5, f"Seasonal {args.run.upper()} Plot\ncycle={args.cycle}",
                ha="center", va="center", fontsize=12)
        ax.axis("off")
        png_path = os.path.join(args.outdir, f"seasonal_plot_{args.run}_{args.cycle}.png")
        fig.tight_layout()
        fig.savefig(png_path, dpi=150)
        plt.close(fig)
        print(f"Created placeholder plot: {png_path}")
    else:
        print("matplotlib not available; created text-only placeholder plot summary.")

    print(f"Wrote summary: {summary}")


if __name__ == "__main__":
    main()
