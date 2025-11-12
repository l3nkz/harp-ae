#!/usr/bin/env bash

export SCRIPTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Include our support libraries
source "$SCRIPTDIR/utils/continuation.inc.sh"
source "$SCRIPTDIR/utils/logging.inc.sh"
source "$SCRIPTDIR/utils/printing.inc.sh"

now=$(date "+%y%m%d_%H%M%S")

printf "HARP Benchmark Suite\n -- OP-Table Measure Script --\n\n"

success=1
if [ ! -e "${SCRIPTDIR}/config.inc.sh" ]; then
    printf "Missing config file 'config.inc.sh'!\n"
    exit 1;
fi
printf "Sourcing the main configuration file\n"

source "$SCRIPTDIR/config.inc.sh"

if [ -z "${scenarios+x}" ]; then
    printf "Missing configuration option 'scenarios'\n"
    success=0
fi

if [ $success -ne 1 ]; then
    printf "Incomplete benchmark configuration, check your 'config.inc.sh'\n"
    exit 1;
fi

# Initialize all optional configuration options
result_dir=${result_dir:-"${now}/results"}
log_dir=${log_dir:-"${now}/logs"}

mkdir -p "$result_dir"
mkdir -p "$log_dir"


export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/empty.yaml"
export TETRIS_SERVER="${SCRIPTDIR}/bin/tetrismockserver"
export TETRIS_LIB="${SCRIPTDIR}/lib/libtetrisclientlegacy.so"

# Construct all possible configurations for this platform
declare -a configs
construct_configs

# Extract the to be measured apps from the scenarios
declare -a apps
for s in ${scenarios[@]}; do
    if [[ $s =~ "|" ]]; then
        continue
    fi

    apps+=($s)
done

step=1
total_step=${#scenarios[@]}
echo -ne "Measuring ${total_step} apps at ${#configs[@]} configurations\n"

for app in ${apps[@]}; do
    app_name=$(save_name $app)

    resultfile="$result_dir/${app_name}.csv"
    this_log_dir="$log_dir/$app_name"
    mkdir -p "$this_log_dir"

    echo -ne "($step/$total_step) Measuring $(human_readable $app)\n"
    current=1
    for c in ${configs[@]}; do
        echo -ne " - ($current/${#configs[@]}) @$c\n"

        serverlog="$this_log_dir/server_${c//,/-}.txt"

        # Start the server
        ${TETRIS_SERVER} -p $TETRIS_PLATFORM -c $c 1>${serverlog} 2>&1 &
        server_pid=$!

        # Start application with the client library attached to it
        applog="$this_log_dir/client_${c//,/-}.txt"

        if [[ "$app" == !* ]]; then
           ${BENCHDIR}/${app_name} 1>"$applog" 2>&1
        elif [[ "$app" == \?* ]]; then
           args=$(cat ${BENCHDIR}/${app_name}.args)
           LD_PRELOAD=${TETRIS_LIB} ${BENCHDIR}/${app_name} ${args} 1>"$applog" 2>&1
        else
           LD_PRELOAD=${TETRIS_LIB} ${BENCHDIR}/${app_name} 1>"$applog" 2>&1
        fi

        # When the application finishes stop everything
        kill $server_pid

        result=$(grep -A1 "time;energy;instruction" $serverlog | tail -n1)
        echo -ne "--> done: $result\n"

        # Store the results in the result csv
        if [ ! -e $resultfile ]; then
            grep "time;energy;instruction" $serverlog | sed 's/.*\(time.*\)/config;\1/' > $resultfile
        fi
        echo "$c;$result" >> $resultfile

        rm -f /tmp/tetris_*

        current=$((current + 1))
    done
    step=$((step + 1))
done
