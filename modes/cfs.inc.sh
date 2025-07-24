function check_cfs() {
    echo 0
}

function warmup_cfs() {
    echo 1
}

function run_cfs() {
    local result_file="$2"
    local log_base_dir="$3"

    local run_log="$log_base_dir/run.log"

    IFS='|' read -r -a progs <<< "$1"

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)

            local prog_log="$log_base_dir/${name}.log"
            local prog_start=$(get_time)

            if [[ "$p" == !* ]]; then
                ${BINDIR}/${name} cfs 1>"$prog_log" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                ${BINDIR}/${name} ${args} 1>"$prog_log" 2>&1
            else
                ${BINDIR}/${name} 1>"$prog_log" 2>&1
            fi

            local exit_code=$?
            echo "exit code: $exit_code" >> "$prog_log"
            echo "total_ms: $(time_diff $prog_start)" >> "$prog_log"
            exit $exit_code
        ) 1>>"$run_log" 2>&1 &
        pid=$!

        echo "Started $(human_readable $p) -> $pid" >> "$run_log"

        prog_pids+=("$pid")
    done

    local all_finished=1

    # Wait for the programs to finish
    for p in ${prog_pids[@]}; do
        wait $p
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "$p did not finish successfully ($exit_code)" >> "$run_log"
            all_finished=0
        fi
    done

    local total_t=$(time_diff $begin_t)
    local total_e=$(energy_diff $begin_e)

    if [ $all_finished -eq 1 ]; then
        echo "cfs;$total_t;$total_e" >> $result_file
        echo 1
    else
        echo 0
    fi
}
