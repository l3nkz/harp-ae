#!/usr/bin/env python3

from pandas import read_csv, DataFrame, concat, Series
from scipy.stats import gmean
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
    os.makedirs(os.path.join(args.output, "multi"), exist_ok=True)

    single_scenarios = []
    multi_scenarios = []
    modes = set()

    print("Collecting results")
    for filename in os.listdir(args.input):
        if filename.endswith(".csv"):
            res = process_file(os.path.join(args.input, filename))

            data = {}
            for mode, result in res["rel_values"].items():
                data[mode] = {
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

    print("Generating post-processed files")
    for mode in modes:
        print (f" - {mode}")
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

        # Collect the data for all single-app scenarios and generate a csv out of it
        for s in single_scenarios:
            for k in data.keys():
                data[k].append(s[mode][k])

        df = DataFrame(data)
        # Sort them first by number of apps and then by their name
        df = df.sort_values(["scenario"])

        # Calculate geomean and add it to the dataframe
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

        df.to_csv(os.path.join(args.output, "single", f"{mode}.csv"), index=False, sep=",")

        # Do the same again for all multi-app scenarios
        # But first clear the data construct
        for k in data.keys():
            data[k].clear()

        for s in multi_scenarios:
            for k in data.keys():
                data[k].append(s[mode][k])

        df = DataFrame(data)
        # Sort them first by number of apps and then by their name
        df = df.sort_values(["nr_apps", "scenario"])

        # Calculate geomean and add it to the dataframe
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

        df.to_csv(os.path.join(args.output, "multi", f"{mode}.csv"), index=False, sep=",")

if __name__ == "__main__":
    run()
