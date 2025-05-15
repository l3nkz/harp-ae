#!/usr/bin/env python3

from pandas import read_csv, DataFrame, concat, Series
from scipy.stats import gmean, gstd
from argparse import ArgumentParser
import sys
import os
from math import sqrt

def process_file(file_path):
    path = os.path.splitext(file_path)[0]
    scenario = os.path.basename(path).replace("_", " + ")
    nr_apps = scenario.count("+") + 1

    print(f" - {scenario} ({nr_apps})".format())

    df = read_csv(file_path, sep=";")
    modes = set(df["mode"])

    results = {
        "name" : scenario,
        "nr_apps" : nr_apps,
        "raw_values" : {},
        "rel_values" : {}
    }
    for mode in modes:
        mean_energy = df[df["mode"] == mode]["energy_uj"].mean()
        mean_time = df[df["mode"] == mode]["time_ms"].mean()
        error_energy = df[df["mode"] == mode]["energy_uj"].std()
        error_time = df[df["mode"] == mode]["time_ms"].std()

        results["raw_values"][mode] = { "energy" : (mean_energy, error_energy), "time" : (mean_time, error_time) }

    cfs_values = results["raw_values"]["cfs"]
    for mode in modes:
        rel_energy = cfs_values["energy"][0] / results["raw_values"][mode]["energy"][0] 
        rel_err_energy = abs(cfs_values["energy"][0] / results["raw_values"][mode]["energy"][0]) \
                       * sqrt((cfs_values["energy"][1]/cfs_values["energy"][0])**2 +
                              (results["raw_values"][mode]["energy"][1] / results["raw_values"][mode]["energy"][0])**2)
        rel_err_max_energy = (rel_energy + rel_err_energy) / rel_energy
        rel_err_min_energy = (rel_energy - rel_err_energy) / rel_energy

        rel_time = cfs_values["time"][0] / results["raw_values"][mode]["time"][0]
        rel_err_time = abs(cfs_values["time"][0] / results["raw_values"][mode]["time"][0]) \
                       * sqrt((cfs_values["time"][1]/cfs_values["time"][0])**2 +
                              (results["raw_values"][mode]["time"][1] / results["raw_values"][mode]["time"][0])**2)
        rel_err_max_time = (rel_time + rel_err_time) / rel_time
        rel_err_min_time = (rel_time - rel_err_time) / rel_time

        results["rel_values"][mode] = { "energy" : (rel_energy, rel_err_max_energy-1, 1-rel_err_min_energy), "time" : (rel_time, rel_err_max_time-1, 1-rel_err_min_time) }

    return results

def save_as_csv(scenarios, mode, value_type, csv_path, geomean=True):
    data = {
        "scenario" : [],
        "nr_apps" : [],
        "energy" : [],
        "err_energy_max" : [],
        "err_energy_min" : [],
        "time" : [],
        "err_time_max" : [],
        "err_time_min" : []
    }

    # Collect the data for all scenarios
    for s in scenarios:
        for k in data.keys():
            data[k].append(s[value_type][mode][k])

    df = DataFrame(data)
    # Sort them first by number of apps and then by their name
    df = df.sort_values(["nr_apps", "scenario"])

    # Calculate geomean and add it to the dataframei
    if geomean:
        mean = Series({
            "scenario" : "GeoMean",
            "nr_apps" : 0,
            "energy" : gmean(data["energy"]),
            "err_energy_max" : 0,
            "err_energy_min" : 0,
            "time" : gmean(data["time"]),
            "err_time_max" : 0,
            "err_time_min" : 0,
        })
        df = concat([df, DataFrame([mean], columns=mean.index)])

    df.to_csv(csv_path, index=False, sep=",")


def run():
    parser = ArgumentParser()
    parser.add_argument("--result-dir", "-i", help="the directory where the measurement results are stored",
                        dest="input", required=True)
    parser.add_argument("--postprocessed-dir", "-o", help="the directory where the post-processed files should be stored",
                        dest="output", required=True)

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print("The result directory does not exist!")
        sys.exit(1)
    if not os.path.exists(args.output):
        os.makedirs(args.output)

    # Create the subdirectories in the output folder
    os.makedirs(os.path.join(args.output, "single"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "single", "raw"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "single", "rel"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "multi"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "multi", "raw"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "multi", "rel"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "all"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "all", "raw"), exist_ok=True)
    os.makedirs(os.path.join(args.output, "all", "rel"), exist_ok=True)

    single_scenarios = []
    multi_scenarios = []
    all_scenarios = []
    modes = set()

    print("Collecting results")
    for filename in os.listdir(args.input):
        if filename.startswith("__"):
            continue

        if filename.endswith(".csv"):
            res = process_file(os.path.join(args.input, filename))

            data = {
                    "raw": {},
                    "rel": {}
            }

            for mode, result in res["raw_values"].items():
                data["raw"][mode] = {
                                "scenario" : res["name"],
                                "nr_apps" : res["nr_apps"],
                                "energy" : result["energy"][0] / 10**6,
                                "err_energy_max" : result["energy"][1],
                                "err_energy_min" : result["energy"][1],
                                "time" : result["time"][0] / 10**3,
                                "err_time_max" : result["time"][1],
                                "err_time_min" : result["time"][1],
                             }

            for mode, result in res["rel_values"].items():
                data["rel"][mode] = {
                                "scenario" : res["name"],
                                "nr_apps" : res["nr_apps"],
                                "energy" : result["energy"][0],
                                "err_energy_max" : result["energy"][1],
                                "err_energy_min" : result["energy"][2],
                                "time" : result["time"][0],
                                "err_time_max" : result["time"][1],
                                "err_time_min" : result["time"][2]
                             }

                modes.add(mode)

            if res["nr_apps"] == 1:
                single_scenarios.append(data)
            else:
                multi_scenarios.append(data)

            all_scenarios.append(data)

    print("Generating post-processed files")
    for mode in modes:
        print (f" - {mode}")
        save_as_csv(single_scenarios, mode, "raw", os.path.join(args.output, "single", "raw", mode + ".csv"), False)
        save_as_csv(multi_scenarios, mode, "raw", os.path.join(args.output, "multi", "raw", mode + ".csv"), False)
        save_as_csv(all_scenarios, mode, "raw", os.path.join(args.output, "all", "raw", mode + ".csv"), False)

        save_as_csv(single_scenarios, mode, "rel", os.path.join(args.output, "single", "rel", mode + ".csv"))
        save_as_csv(multi_scenarios, mode, "rel", os.path.join(args.output, "multi", "rel", mode + ".csv"))
        save_as_csv(all_scenarios, mode, "rel", os.path.join(args.output, "all", "rel", mode + ".csv"))

if __name__ == "__main__":
    run()
