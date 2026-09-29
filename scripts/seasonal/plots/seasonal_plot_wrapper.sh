#!/bin/bash
# Minimal seasonal plots wrapper

set -euo pipefail

usage() {
  echo "Usage: $0 --run det|ens --cycle YYYYMMDDHH --workdir DIR --outdir DIR"
  exit 1
}

RUN=""
CYCLE=""
WORKDIR=""
OUTDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN="$2"; shift 2 ;;
    --cycle) CYCLE="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --outdir) OUTDIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[[ -n "${RUN}" ]] || usage
[[ -n "${CYCLE}" ]] || usage
[[ -n "${WORKDIR}" ]] || usage
[[ -n "${OUTDIR}" ]] || usage

mkdir -p "${WORKDIR}" "${OUTDIR}"

python "${HOMEevs:-${PWD}}/scripts/seasonal/plots/seasonal_plot_maps.py" \
  --run "${RUN}" \
  --cycle "${CYCLE}" \
  --workdir "${WORKDIR}" \
  --outdir "${OUTDIR}"

echo "Seasonal plot wrapper completed for run=${RUN}, cycle=${CYCLE}"
