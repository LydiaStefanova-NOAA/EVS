import matplotlib
matplotlib.use("TkAgg")  # Interactive X11 backend

import matplotlib.pyplot as plt
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import numpy as np
import xarray as xr

fpath = (
    "/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/evs/v2.0/stats/seasonal/"
    "sfs_b2.202510/grid_stat_sfs_b2_ensmean_HGT500_init20251001_valid202510/"
    "grid_stat_000000L_20251001_000000V_pairs.nc"
)
ds = xr.open_dataset(fpath)

# Extract fields
fcst       = ds["FCST_HGT_500mb_0_all_all_FULL"].squeeze()
fcst_climo = ds["FCST_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()
obs        = ds["OBS_HGT_500mb_0_all_all_FULL"].squeeze()
obs_climo  = ds["OBS_CLIMO_MEAN_HGT_500mb_0_all_all_FULL"].squeeze()

# Calculate anomalies using their respective climatologies
fcst_anom = fcst - fcst_climo
obs_anom  = obs - obs_climo

# Coordinate detection
lat = ds["lat"].values if "lat" in ds else ds["latitude"].values
lon = ds["lon"].values if "lon" in ds else ds["longitude"].values

# Create side-by-side comparison
fig, axes = plt.subplots(
    2, 1, figsize=(11, 8),
    subplot_kw={"projection": ccrs.PlateCarree(central_longitude=180)}
)

clevs = np.arange(-120, 130, 20)
cmap = "RdBu_r"

panels = [
    (obs_anom, "CORe Observed HGT500 Anomaly (Valid: Oct 2025)", axes[0]),
    (fcst_anom, "SFS b2 Ens Mean HGT500 Anomaly (Init: 2025-10-01, Lead 0)", axes[1]),
]

for field, title, ax in panels:
    ax.coastlines(resolution="110m", linewidth=0.8)
    ax.add_feature(cfeature.BORDERS, linestyle=":")
    cf = ax.contourf(
        lon, lat, field, levels=clevs, cmap=cmap,
        extend="both", transform=ccrs.PlateCarree()
    )
    ax.set_title(title, fontsize=11, fontweight="bold")

cbar = fig.colorbar(cf, ax=axes, orientation="horizontal", fraction=0.05, pad=0.08)
cbar.set_label("500 hPa Height Anomaly (gpm)", fontsize=10)

plt.show()
