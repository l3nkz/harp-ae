function check_cfs() {
    echo 0
}

function warmup_cfs() {
    echo 1
}

function run_cfs() {
    local result_file="$2"
    local log_base_dir="$3"

    IFS='|' read -r -a progs <<< "$1"

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)

            local proglog="$log_base_dir/${name}.log"
            local prog_start=$(get_time)

            if [[ "$p" == !* ]]; then
                ${BINDIR}/${name} cfs 1>"$proglog" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                ${BINDIR}/${name} ${args} 1>"$proglog" 2>&1
            else
                ${BINDIR}/${name} 1>"$proglog" 2>&1
            fi

            echo "total_ms: $(time_diff $prog_start)" >> "$proglog"
        ) &
        prog_pids+=("$!")
    done

    # Wait for the programs to finish
    for p in ${prog_pids[@]}; do
        wait $p
    done

    local total_t=$(time_diff $begin_t)
    local total_e=$(energy_diff $begin_e)

    echo "cfs;$total_t;$total_e" >> $result_file
    echo 1
}
