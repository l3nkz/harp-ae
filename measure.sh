#!/usr/bin/env bash

export SCRIPTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Include our support libraries
source "$SCRIPTDIR/utils/continuation.inc.sh"
source "$SCRIPTDIR/utils/logging.inc.sh"
source "$SCRIPTDIR/utils/printing.inc.sh"

now=$(date "+%y%m%d_%H%M%S")

printf "E-Mapper Benchmark Suite\n -- Measure Script --\n\n"

if [ ! -e "${SCRIPTDIR}/config.inc.sh" ]; then
    printf "Missing config file 'config.inc.sh'!\n"
    exit 1;
fi


printf "Sourcing the main configuration file\n"

success=1
source "$SCRIPTDIR/config.inc.sh"

if [ -z "${scenarios+x}" ]; then
    printf "Missing configuration option 'scenarios'\n"
    success=0
fi
if [ -z "${runs+x}" ]; then
    printf "Missing configuration option 'runs'\n"
    success=0
fi
if [ -z "${modes+x}" ]; then
    printf  "Missing configuration option 'modes'\n"
    success=0
fi

if [ $success -ne 1 ]; then
    printf "Incomplete benchmark configuration, check your 'config.inc.sh'\n"
    exit 1;
fi

# Initialize all optional configuration options
result_dir=${result_dir:-"${now}/results"}
log_dir=${log_dir:-"${now}/logs"}
trace_dir=${trace_dir:-"${now}/traces"}
learn_dir=${learn_dir:-"${now}/learn-db"}

printf "Running the following configuration:\n"
printf " platform: ${platform_name}\n"
printf " ${#scenarios[@]} scenario(s): ${scenarios[*]}\n"
printf " ${runs} run(s)\n"
printf " ${#modes[@]} mode(s): ${modes[*]}\n"
printf "Output Directories:\n"
printf " - results: ${result_dir}\n"
printf " - logs: ${log_dir}\n"
printf " - traces: ${trace_dir}\n"
printf " - learning DB: ${learn_dir}\n"

printf "Sourcing mode configurations:\n"

success=1
for m in ${modes[@]}; do
    printf " -> $m"
    if [ ! -e "${SCRIPTDIR}/modes/${m}.inc.sh" ]; then
        printf " XX Missing mode config file 'modes/${m}.inc.sh' !!\n"
        success=0
    else
        printf " success\n"
        source "${SCRIPTDIR}/modes/${m}.inc.sh"
    fi
done

if [ $success -ne 1 ]; then
    printf "Incomplete modes configuration!\n"
    exit 1;
fi


printf "Checking the system configuration:\n"
success=1

printf " - Access to energy sensors "
get_energy 1>/dev/null 2>&1
if [ $? -ne 0 ]; then
    printf "NO!\n"
    success=0
else
    printf "Yes\n"
fi

printf " - Access to perf "
if [ $UID -ne 0 -a $(cat /proc/sys/kernel/perf_event_paranoid) -ne -1 ]; then
    printf "NO!\n"
    success=0
else
    printf "Yes\n"
fi

printf " - Access to all tools of the benchmarking modes\n"
for m in ${modes[@]}; do
    printf "  - $m "
    result=$(check_$m)
    if [ $result -eq 1 ]; then
        printf "NO!\n"
        success=0
    else
        printf "Yes\n"
    fi
done

printf " - Access to all scenario binaries\n"
for s in ${scenarios[@]}; do
    printf "  - $(human_readable $s) "

    IFS='|' read -r -a progs <<< "$s"

    all_good=1
    for p in ${progs[@]}; do
        p_name=$(save_name $p)

        if [ ! -x  "${BINDIR}/${p_name}" ]; then
            all_good=0
            printf "NO! $p_name missing!\n"
            break
        fi

        if [[ "$p" == \?* ]]; then
            if [ ! -e  "${BINDIR}/${p_name}.args" ]; then
                all_good=0
                printf "NO! $p_name args missing!\n"
                break
            fi
        fi
    done
    if [ $all_good -eq 1 ]; then
        printf "Yes\n"
    else
        success=0
        break
    fi
done

if [ $success -ne 1 ]; then
    printf "Incomplete system configuration!\n"
    exit 1;
fi


printf "Checking the environment:\n"
success=1
if [ $success -ne 1 ]; then
    printf "Incomplete environment!\n"
    exit 1;
fi

continuation=${continuation:-0}
if [ $continuation -eq 1 ]; then
    printf "Trying to restore previous run …\n"
    restore
else
    # Create the necessary output directories
    mkdir -p "$result_dir"
    mkdir -p "$log_dir"
    mkdir -p "$trace_dir"
    mkdir -p "$learn_dir"
fi

step=1
total_step=${#scenarios[@]}
for s in ${scenarios[@]}; do
    pname="$(human_readable $s)"
    printf "(${step}/${total_step}) $pname\n"

    this_result_file="${result_dir}/$(save_name $s).csv"
    echo "mode;time_ms;energy_uj" > "$this_result_file"

    for m in ${modes[@]}; do
        printf " => ${m}: ";

        # Initialize and create output directories
        this_log_dir_base="${log_dir}/$(save_name $s)/${m}"
        this_trace_dir_base="${trace_dir}/$(save_name $s)/${m}"

        this_learn_dir="${learn_dir}/$(save_name $s)/${m}"
 
        mkdir -p "${this_learn_dir}"

        warmup_log_dir="${this_log_dir_base}/warmup"
        warmup_trace_dir="${this_trace_dir_base}/warmup"
        mkdir -p "$warmup_log_dir"
        mkdir -p "$warmup_trace_dir"

        # Before making the measurements call the warmup function of the mode
        printf "WU ";
        success=$(warmup_${m} "$s" "$warmup_log_dir" "$warmup_trace_dir" "$this_learn_dir")
        if [ $success -eq 1 ]; then
            # Warm up is done, do the actual measurements now
            for r in $(seq 1 $runs); do
                tries=0
                success=0
                while [ $success -ne 1 ]; do
                    printf "$r "

                    # Initialize the output directories for this run
                    this_log_dir="${this_log_dir_base}/run_$r-$tries"
                    this_trace_dir="${this_trace_dir_base}/run_$r-$tries"

                    mkdir -p "${this_log_dir}"
                    mkdir -p "${this_trace_dir}"

                    success=$(run_${m} "$s" "$this_result_file" "$this_log_dir" "$this_trace_dir" "$this_learn_dir")
                    if [ $success -ne 1 ]; then
                        printf "!! "
                        tries=$((tries + 1))
                    fi
                done
                checkpoint "$s" "$m" "$r"
            done
        else 
            printf "Failure!"
        fi
        printf "\n"
    done

    step=$((step + 1))
done
