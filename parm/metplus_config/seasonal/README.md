# EVS Seasonal METplus Starter Configs

This directory contains starter METplus templates for EVS `seasonal` component:

- `det/` deterministic seasonal verification (GridStat)
- `ens/` probabilistic/ensemble seasonal verification (EnsembleStat)
- `common/` shared config fragments

## How to use (starter)

For deterministic:
```bash
run_metplus.py \
  ${HOMEevs}/parm/metplus_config/seasonal/det/metplus_det.conf
```

For probabilistic/ensemble:
```bash
run_metplus.py \
  ${HOMEevs}/parm/metplus_config/seasonal/ens/metplus_ens.conf
```

Environment variables expected by these templates:

- `EVS_SEASONAL_METPLUS_ROOT` (default: this directory)
- `FCST_INPUT_DIR`
- `OBS_INPUT_DIR`
- `METPLUS_OUT_DIR`
- `RUN` (`det` or `ens`)
- `PDY`, `cyc`

These are starter templates and should be tuned to your actual model/obs file formats.
