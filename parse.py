from pathlib import Path
import pandas as pd

base_dir = Path("/lfs/h2/emc/vpppg/noscrub/lydia.b.stefanova/evs/v2.0/stats/seasonal/sfs_b2.202510")

# Find all sal1l2 files matching the pattern
sal1l2_files = sorted(base_dir.glob("grid_stat_sfs_b2_ensmean_HGT500_*/*_sal1l2.txt"))

# Read and combine
df_list = []
for f in sal1l2_files:
    temp_df = pd.read_csv(f, sep=r"\s+")
    # Optional: extract init date from parent directory name
    temp_df["INIT_DIR"] = f.parent.name
    df_list.append(temp_df)

df_all = pd.concat(df_list, ignore_index=True)
print(f"Loaded {len(df_all)} lines across {len(sal1l2_files)} files.")

import numpy as np

# Uncentered ACC
df_all["ACC_UNCNTR"] = df_all["FOABAR"] / np.sqrt(df_all["FFABAR"] * df_all["OOABAR"])

# Centered ACC (Pearson correlation of anomalies)
cov = df_all["FOABAR"] - (df_all["FABAR"] * df_all["OABAR"])
var_fcst = df_all["FFABAR"] - (df_all["FABAR"] ** 2)
var_obs  = df_all["OOABAR"] - (df_all["OABAR"] ** 2)

df_all["ACC_CNTR"] = cov / np.sqrt(var_fcst * var_obs)

# View results by verification mask (VX_MASK)
print(df_all[["INIT_DIR", "VX_MASK", "ACC_CNTR", "ACC_UNCNTR"]])

print(df_all[["INIT_DIR", "FABAR", "OABAR", "FOABAR", "ACC_CNTR", "ACC_UNCNTR"]])
