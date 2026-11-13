import numpy as np
import xarray as xr

# Load datasets
ds0 = xr.open_dataset("/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/evs/v2.0/stats/seasonal/sfs_b2.202510/grid_stat_sfs_b2_ensmean_HGT500_init20251001_valid202510/grid_stat_000000L_20251001_000000V_pairs.nc")
ds1 = xr.open_dataset("/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/evs/v2.0/stats/seasonal/sfs_b2.202510/grid_stat_sfs_b2_ensmean_HGT500_init20250901_valid202510/grid_stat_000000L_20251001_000000V_pairs.nc")

# 1. Correctly compute Lead 0 Anomalies
fcst0       = ds0["FCST_HGT_500mb_0_all_all_FULL"].squeeze()
fcst_climo0 = ds0["FCST_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()
obs0        = ds0["OBS_HGT_500mb_0_all_all_FULL"].squeeze()
obs_climo0  = ds0["OBS_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()

fcst_anom0 = fcst0 - fcst_climo0
obs_anom0  = obs0 - obs_climo0

# 2. Correctly compute Lead 1 Anomalies
fcst1       = ds1["FCST_HGT_500mb_0_all_all_FULL"].squeeze()
fcst_climo1 = ds1["FCST_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()
obs1        = ds1["OBS_HGT_500mb_0_all_all_FULL"].squeeze()
obs_climo1  = ds1["OBS_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()

fcst_anom1 = fcst1 - fcst_climo1
obs_anom1  = obs1 - obs_climo1

# Quick Sanity Check: Anomaly ranges should be around -150 to +150 gpm
print(f"Obs Anom Range:   {float(obs_anom0.min()):.1f} to {float(obs_anom0.max()):.1f} gpm")
print(f"Lead 0 Anom Range: {float(fcst_anom0.min()):.1f} to {float(fcst_anom0.max()):.1f} gpm")
print(f"Lead 1 Anom Range: {float(fcst_anom1.min()):.1f} to {float(fcst_anom1.max()):.1f} gpm")

import matplotlib
matplotlib.use("Agg")  # Reliable on WCOSS2
import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature

def compute_field_acc(f_prime, o_prime):
    f = f_prime.values.flatten()
    o = o_prime.values.flatten()
    valid = ~np.isnan(f) & ~np.isnan(o)
    f, o = f[valid], o[valid]

    acc_uncntr = np.sum(f * o) / np.sqrt(np.sum(f**2) * np.sum(o**2))
    f_c = f - np.mean(f)
    o_c = o - np.mean(o)
    acc_cntr = np.sum(f_c * o_c) / np.sqrt(np.sum(f_c**2) * np.sum(o_c**2))
    return acc_cntr, acc_uncntr

acc_c0, acc_u0 = compute_field_acc(fcst_anom0, obs_anom0)
acc_c1, acc_u1 = compute_field_acc(fcst_anom1, obs_anom1)

print(f"Lead 0 (init20251001) - Centered ACC: {acc_c0:.4f}, Uncentered ACC: {acc_u0:.4f}")
print(f"Lead 1 (init20250901) - Centered ACC: {acc_c1:.4f}, Uncentered ACC: {acc_u1:.4f}")

# Plotting
lat = ds0["lat"].values if "lat" in ds0 else ds0["latitude"].values
lon = ds0["lon"].values if "lon" in ds0 else ds0["longitude"].values

fig, axes = plt.subplots(
    3, 1, figsize=(11, 12),
    subplot_kw={"projection": ccrs.PlateCarree(central_longitude=180)}
)

clevs = np.arange(-120, 130, 20)
cmap = "RdBu_r"

panels = [
    (obs_anom0, "CORe Observed HGT500 Anomaly (Valid: Oct 2025)", axes[0]),
    (fcst_anom0, f"Lead 0 (Init: 2025-10-01) Ens Mean Anom | ACC: {acc_c0:.2f}", axes[1]),
    (fcst_anom1, f"Lead 1 (Init: 2025-09-01) Ens Mean Anom | ACC: {acc_c1:.2f}", axes[2]),
]

for field, title, ax in panels:
    ax.coastlines(resolution="110m", linewidth=0.8)
    ax.add_feature(cfeature.BORDERS, linestyle=":")
    cf = ax.contourf(lon, lat, field, levels=clevs, cmap=cmap, extend="both", transform=ccrs.PlateCarree())
    ax.set_title(title, fontsize=11, fontweight="bold")

cbar = fig.colorbar(cf, ax=axes, orientation="horizontal", fraction=0.045, pad=0.05)
cbar.set_label("500 hPa Height Anomaly (gpm)", fontsize=10)

plt.savefig("hgt500_anomaly_comparison.png", dpi=150, bbox_inches="tight")
print("Saved to hgt500_anomaly_comparison.png")
