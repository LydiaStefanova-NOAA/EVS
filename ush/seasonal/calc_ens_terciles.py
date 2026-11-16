#!/usr/bin/env python3
"""
Compute ensemble tercile probabilities (below, near, above) and dominant tercile
category (1=below, 2=near, 3=above) against lead-dependent model climatology.

Usage:
    calc_ens_terciles.py <out_prob.nc> <climo.nc> <ensmean.nc> <var1,var2,...> <mem0.nc> [<mem1.nc> ...]
"""
import sys
import numpy as np
import xarray as xr


def main():
    if len(sys.argv) < 6:
        sys.stderr.write(
            "Usage: calc_ens_terciles.py <out_prob.nc> <climo.nc> <ensmean.nc> "
            "<var1,var2,...> <mem0.nc> [<mem1.nc> ...]\n"
        )
        sys.exit(1)

    out_prob_path = sys.argv[1]
    climo_path = sys.argv[2]
    mean_path = sys.argv[3]
    target_vars = [v for v in sys.argv[4].split(",") if v]
    member_paths = sys.argv[5:]

    if not target_vars:
        sys.stderr.write("ERROR: No target variables provided to calc_ens_terciles.py.\n")
        sys.exit(1)

    ds_clim = xr.open_dataset(climo_path)
    ds_mean = xr.open_dataset(mean_path)

    member_dsets = [xr.open_dataset(p) for p in member_paths]
    ds_ens = xr.concat(member_dsets, dim="ens")

    out_ds = xr.Dataset(coords=ds_mean.coords)

    for var in target_vars:
        if var not in ds_mean:
            sys.stderr.write(f"ERROR: Configured variable '{var}' missing from forecast {mean_path}\n")
            sys.exit(1)

        p33_key = f"{var}_p33"
        p67_key = f"{var}_p67"
        if p33_key not in ds_clim or p67_key not in ds_clim:
            sys.stderr.write(f"ERROR: Missing '{p33_key}' and/or '{p67_key}' in {climo_path}\n")
            sys.exit(1)

        ens_vals = ds_ens[var].values
        p33_vals = ds_clim[p33_key].values
        p67_vals = ds_clim[p67_key].values

        if ens_vals.shape[1:] != p33_vals.shape or ens_vals.shape[1:] != p67_vals.shape:
            sys.stderr.write(
                f"ERROR: Shape mismatch for '{var}': forecast slice {ens_vals.shape[1:]} vs "
                f"climo {p33_vals.shape} / {p67_vals.shape}\n"
            )
            sys.exit(1)

        pb = np.mean(ens_vals < p33_vals[np.newaxis, ...], axis=0).astype(np.float32)
        pa = np.mean(ens_vals > p67_vals[np.newaxis, ...], axis=0).astype(np.float32)
        pn = np.clip(1.0 - (pb + pa), 0.0, 1.0).astype(np.float32)

        # Dominant tercile category: 1 = below, 2 = near, 3 = above
        dom_cat = np.full(pb.shape, 2, dtype=np.float32)
        dom_cat[(pb > pn) & (pb >= pa)] = 1
        dom_cat[(pa > pn) & (pa > pb)] = 3

        nan_mask = np.isnan(ens_vals[0])
        pb[nan_mask] = np.nan
        pn[nan_mask] = np.nan
        pa[nan_mask] = np.nan
        dom_cat[nan_mask] = np.nan

        dims = ds_mean[var].dims
        out_ds[f"{var}_prob_below"] = xr.DataArray(
            pb, dims=dims, attrs={"long_name": f"{var} probability below normal", "units": "1"}
        )
        out_ds[f"{var}_prob_near"] = xr.DataArray(
            pn, dims=dims, attrs={"long_name": f"{var} probability near normal", "units": "1"}
        )
        out_ds[f"{var}_prob_above"] = xr.DataArray(
            pa, dims=dims, attrs={"long_name": f"{var} probability above normal", "units": "1"}
        )
        out_ds[f"{var}_dom_cat"] = xr.DataArray(
            dom_cat,
            dims=dims,
            attrs={"long_name": f"{var} dominant tercile category (1=below,2=near,3=above)", "units": "1"},
        )

    for d in member_dsets:
        d.close()
    ds_clim.close()
    ds_mean.close()

    out_ds.to_netcdf(out_prob_path, format="NETCDF3_64BIT")
    print(" ".join(target_vars))


if __name__ == "__main__":
    main()
