#!/usr/bin/env python3
"""
Minimal EVS seasonal stats runner starter.
This script is invoked by JEVS_STATS_SEASONAL.
It reads the seasonal config and writes a simple verification summary file.
"""

import argparse
import os
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(description="EVS seasonal stats starter")
    parser.add_argument("--run", required=True, choices=["det", "ens"])
    parser.add_argument("--cycle", required=True)
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--outdir", required=True)
    return parser.parse_args()


def main():
    args = parse_args()

    os.makedirs(args.workdir, exist_ok=True)
    os.makedirs(args.outdir, exist_ok=True)

    models = os.environ.get("SEASONAL_MODELS", "cfs")
    obs = os.environ.get("SEASONAL_OBS", "era5")
    leads = os.environ.get("SEASONAL_LEADS", "1 2 3 4 5 6")
    domains = os.environ.get("SEASONAL_DOMAINS", "global")

    out_file = os.path.join(args.outdir, f"seasonal_stats_{args.run}_{args.cycle}.txt")
    with open(out_file, "w", encoding="utf-8") as fh:
        fh.write(f"component=seasonal\n")
        fh.write(f"run={args.run}\n")
        fh.write(f"cycle={args.cycle}\n")
        fh.write(f"timestamp={datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}\n")
        fh.write(f"models={models}\n")
        fh.write(f"obs={obs}\n")
        fh.write(f"leads={leads}\n")
        fh.write(f"domains={domains}\n")
        fh.write("status=success\n")

    print(f"Wrote seasonal stats summary: {out_file}")


if __name__ == "__main__":
    main()
