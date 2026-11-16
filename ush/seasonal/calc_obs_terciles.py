#!/usr/bin/env python3
"""
Compute realized observation tercile category (1=below, 2=near, 3=above) and
binary event indicators (<var>_below, <var>_near, <var>_above) against
monthly observation climatology thresholds (<var>_p33, <var>_p67).

Usage:
    calc_obs_terciles.py <out_cat.nc> <climo.nc> <obs.nc> <vmonth_int> <var1,var2,...>
"""
import sys
import numpy as np
import xarray as xr


def main():
    if len(sys.argv) != 6:
        sys.stderr.write(
            "Usage: calc_obs_terciles.py <out_cat.nc> <climo.nc> <obs.nc> <vmonth_int> <var1,var2,...>\n"
        )
        sys.exit(1)

    out_cat_path = sys.argv[1]
    climo_path = sys.argv[2]
    obs_path = sys.argv[3]
    vmonth = int(sys.argv[4])
    target_vars = [v for v in sys.argv[5].split(",") if v]

    if not target_vars:
        sys.stderr.write("ERROR: No target variables provided to calc_obs_terciles.py.\n")
        sys.exit(1)

    ds_clim = xr.open_dataset(climo_path)
    ds_obs = xr.open_dataset(obs_path)

    out_ds = xr.Dataset(coords=ds_obs.coords)

    for var in target_vars:
        if var not in ds_obs:
            sys.stderr.write(f"ERROR: Configured obs variable '{var}' missing from {obs_path}\n")
            sys.exit(1)

        p33_key = f"{var}_p33"
        p67_key = f"{var}_p67"
        if p33_key not in ds_clim or p67_key not in ds_clim:
            sys.stderr.write(f"ERROR: Missing '{p33_key}' and/or '{p67_key}' in {climo_path}\n")
            sys.exit(1)

        obs_vals = ds_obs[var].values
        p33_vals = ds_clim[p33_key].values
        p67_vals = ds_clim[p67_key].values

        # Extract target calendar month if climatology holds all 12 months
        if p33_vals.ndim == 3 and p33_vals.shape[0] == 12:
            p33_vals = p33_vals[vmonth - 1]
            p67_vals = p67_vals[vmonth - 1]

        # Align singleton time dimension between observation and climatology
        if obs_vals.ndim == 3 and p33_vals.ndim == 2:
            p33_vals = p33_vals[np.newaxis, ...]
            p67_vals = p67_vals[np.newaxis, ...]
        elif obs_vals.ndim == 2 and p33_vals.ndim == 3 and p33_vals.shape[0] == 1:
            p33_vals = p33_vals[0]
            p67_vals = p67_vals[0]

        if obs_vals.shape != p33_vals.shape or obs_vals.shape != p67_vals.shape:
            sys.stderr.write(
                f"ERROR: Shape mismatch for '{var}': obs {obs_vals.shape} vs "
                f"climo {p33_vals.shape} / {p67_vals.shape}\n"
            )
            sys.exit(1)

        invalid = np.isnan(obs_vals) | np.isnan(p33_vals) | np.isnan(p67_vals)

        below = np.where(obs_vals < p33_vals, 1.0, 0.0).astype(np.float32)
        above = np.where(obs_vals > p67_vals, 1.0, 0.0).astype(np.float32)
        near = np.where((obs_vals >= p33_vals) & (obs_vals <= p67_vals), 1.0, 0.0).astype(np.float32)

        # Realized tercile category: 1 = below, 2 = near, 3 = above
        cat = np.full(obs_vals.shape, 2.0, dtype=np.float32)
        cat[obs_vals < p33_vals] = 1.0
        cat[obs_vals > p67_vals] = 3.0

        below[invalid] = np.nan
        near[invalid] = np.nan
        above[invalid] = np.nan
        cat[invalid] = np.nan

        dims = ds_obs[var].dims
        out_ds[f"{var}_cat"] = xr.DataArray(
            cat,
            dims=dims,
            attrs={"long_name": f"{var} realized tercile category (1=below,2=near,3=above)", "units": "1"},
        )
        out_ds[f"{var}_below"] = xr.DataArray(
            below, dims=dims, attrs={"long_name": f"{var} below-normal indicator", "units": "1"}
        )
        out_ds[f"{var}_near"] = xr.DataArray(
            near, dims=dims, attrs={"long_name": f"{var} near-normal indicator", "units": "1"}
        )
        out_ds[f"{var}_above"] = xr.DataArray(
            above, dims=dims, attrs={"long_name": f"{var} above-normal indicator", "units": "1"}
        )

    ds_clim.close()
    ds_obs.close()

    out_ds.to_netcdf(out_cat_path, format="NETCDF3_64BIT")
    print(" ".join(target_vars))


if __name__ == "__main__":
    main()
