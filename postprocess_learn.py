#!/usr/bin/env python3

import os, csv, sys
from argparse import ArgumentParser

def combine_csv_files(directory, out_path):
    combined_rows = []

    # Iterate through each file in the directory
    for filename in os.listdir(directory):
        # Ensure we only process CSV files
        if filename.startswith("learning"):
            # Extract the scheduler and scenario from the filename
            scenario = filename[len("learning_"):-4]
            num_apps = len(scenario.split("_"))

            # Open and read the file
            with open(os.path.join(directory, filename), "r") as f:
                reader = csv.reader(f, delimiter=";")
                next(reader)  # Skip the header

                # For each row in the file, append to our combined list
                for row in reader:
                    run, time_ms, energy_uj, stages = row
                    combined_rows.append([scenario, num_apps, run, time_ms, energy_uj, stages])

    # Sanity check: Ensure a file exists for every combination
    all_scenarios = set(v[0] for v in combined_rows)
    for row in combined_rows:
        row[0] = row[0].replace("_", " + ")

    # Write the combined rows to a new CSV file
    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["scenario", "num_apps", "run", "time_ms", "energy_uj", "stages"])
        writer.writerows(combined_rows)

def combine_base_files(directory, out_path):
    combined_rows = []

    # Iterate through each file in the directory
    for filename in os.listdir(directory):
        # Ensure we only process CSV files
        if filename.endswith(".csv"):
            # Extract the scheduler and scenario from the filename
            scenario = filename[:-4]
            num_apps = len(scenario.split("_"))

            # Open and read the file
            with open(os.path.join(directory, filename), "r") as f:
                reader = csv.reader(f, delimiter=";")
                next(reader)  # Skip the header

                # For each row in the file, append to our combined list
                for row in reader:
                    scheduler, time_ms, energy_uj = row
                    combined_rows.append([scheduler, scenario, num_apps, time_ms, energy_uj])

    # Sanity check: Ensure a file exists for every combination
    all_schedulers = set(v[0] for v in combined_rows)
    all_scenarios = set(v[1] for v in combined_rows)
    print("All scheduler: ", all_schedulers)
    print("All scenarios: ", all_scenarios)

    for scheduler in all_schedulers:
        for scenario in all_scenarios:
            found = False
            for row in combined_rows:
                if row[0] == scheduler and row[1] == scenario:
                    found = True
            if not found:
                print(
                    f"Missing results for scheduler '{scheduler}' and scenario '{scenario}'"
                )
                sys.exit(1)

    for row in combined_rows:
        row[1] = row[1].replace("_", " + ")

    # Write the combined rows to a new CSV file
    with open(out_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["scheduler", "scenario", "num_apps", "time_ms", "energy_uj"])
        writer.writerows(combined_rows)

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("--learn-dir", "-l", help="the directory where the learning measurement results are stored",
                        dest="learn", required=True)
    parser.add_argument("--base-dir", "-b", help="the directory where the baseline measurement results are stored",
                        dest="base", required=True)
    parser.add_argument("--postprocessed-dir", "-o", help="the directory where the post-processed files should be stored",
                        dest="output", required=True)

    args = parser.parse_args()

    if not os.path.exists(args.learn):
        print("The learning result directory does not exist!")
        sys.exit(1)
    if not os.path.exists(args.base):
        print("The baseline result directory does not exist!")
        sys.exit(1)
    if not os.path.exists(args.output):
        os.makedirs(args.output)

    combine_base_files(args.base, os.path.join(args.output, "base.csv"))
    combine_learn_files(args.learn, os.path.join(args.output, "learn.csv"))
