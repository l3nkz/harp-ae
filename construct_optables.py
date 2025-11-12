#!/usr/bin/env python3

from argparse import ArgumentParser
from pandas import read_csv
import yaml
from paretoset import paretoset
import sys
import os


def construct_optable(app_name, pf_name, df, out_path):
    base_data = { 
        "application" : app_name,
        "platform" : pf_name,
        "type" : "OMP",
        "mapping_template": {
            "metadata" : ["utility", "power", "nr_threads"]
        },
        "mappings" : []}

    for i, row in df.iterrows():
        cores = row["config"].split(",")
        utility = row["utility"]
        power = row["power_mw"]
        nr_threads = len(cores);

        mapping_data = {
            "name" : "mapping" + str(i),
            "metadata" : [utility, power, nr_threads],
            "cores" : cores
        }

        base_data["mappings"].append(mapping_data)

    with open(out_path, 'w') as outfile:
        yaml.dump(base_data, outfile, default_flow_style=False)

def pareto_optimize(df, platform):
    df = df.groupby("config", as_index=False).mean()

    if platform == "raptor":
        df["p_threads"] = df["config"].str.count("P")
        p_cores = []
        for _, r in df.iterrows():
            p = [i[:3] for i in r["config"].split(",") if i.startswith("P")]
            p_cores.append(len(set(p)))
        df["p_cores"] = p_cores
        df["e_cores"] = df["config"].str.count("E")
    elif platform == "odroid":
        p_cores = []
        e_cores = []
        for _, r in df.iterrows():
            if r["config"].startswith("ARM"):
                bigs = []
                littles = []

                for c in r["config"].split(","):
                    if int(c[-1]) < 4:
                        littles.append(c)
                    else:
                        bigs.append(c)
                p_cores.append(len(bigs))
                e_cores.append(len(littles))

        df["p_cores"] = p_cores
        df["p_threads"] = p_cores
        df["e_cores"] = e_cores

        # We don't have an utility score by default on odroid, so mimic it
        min_total_ms = df["total_ms"].min()
        df["ips"] = min_total_ms/df["total_ms"]

    static_power = 9800 if platform == "raptor" else 1200
    df["power_mw"] = df["energy"]/df["time"] - static_power

    if not "utility" in df.columns:
        df["utility"] = df["ips"]

    mask = paretoset(df[["utility", "power_mw", "p_cores", "e_cores"]], sense=["max", "min", "min", "min"])
    pareto_df = df[mask]

    return pareto_df

def main():
    parser = ArgumentParser()
    parser.add_argument("--result-dir", "-i", help="the directory where the measurement results are stored",
                        dest="input", required=True)
    parser.add_argument("--output-dir", "-o", help="the base directory where the op-tables should be stored",
                        dest="output", required=True)
    parser.add_argument("--platform", "-p", help="the name of the platform that was measured",
                        dest="platform", required=True)

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print("The result directory does not exist!")
        sys.exit(1)
    if not os.path.exists(args.output):
        os.makedirs(args.output)

    platform = args.platform

    if platform == "raptor":
        pf_name = "raptor-lake-8P16E"
    else:
        pf_name = platform
    out_base = os.path.join(args.output, pf_name, "mappings")
    os.makedirs(out_base, exist_ok=True)

    print("Collecting results")
    for filename in os.listdir(args.input):
        if filename.startswith("__"):
            continue

        if filename.endswith(".csv"):
            app_name = filename[:-4]
            print(" -> {}".format(app_name))

            df = read_csv(os.path.join(args.input, filename), sep=";")

            pareto_df = pareto_optimize(df, platform)
            construct_optable(app_name, pf_name, pareto_df, os.path.join(out_base, app_name + '.yaml'))

if __name__ == "__main__":
    main()
