#/usr/bin/env python3

from pandas import read_csv, concat
from argparse import ArgumentParser
import os
import sys

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

    for filename in os.listdir(args.input):
        if filename.endswith(".csv"):
            # get the name and the mode
            mode, name = filename[:-4].split("__")

            outname = name + ".csv"

            if mode == "tetris_balanced":
                mode = "tetris"

            df = read_csv(filename, sep=";")
            df["energy_uj"] = (df["big_j"] + df["little_j"] + df["dram_j"]) * 10**6
            df["mode"] = mode

            outdf = concat([df["mode"],df["time_ms"], df["energy_uj"]], axis=1)

            if os.path.exists(os.path.join(args.output, outname)):
                prev_df = read_csv(os.path.join(args.output, outname), sep=";")

                outdf = concat([prev_df, outdf])

            outdf.to_csv(os.path.join(args.output, outname), sep=";", index=False)

if __name__ == "__main__":
    run()
