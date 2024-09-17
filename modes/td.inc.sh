export TD_SERVER="${SCRIPTDIR}/bin/tetristd"
export TD_LIB="${SCRIPTDIR}/lib/libtetristdclient.so"

function check_td() {
    local failure=0
    if [ ! -x "$TD_SERVER" ]; then
        failure=1
    fi
    if [ ! -e "$TD_LIB" ]; then
        failure=1
    fi

    if [ ! -e /proc/ipc_scores ]; then
        echo "ITD scores not accessible! Wrong kernel?" >&2
        failure=1
    fi

    echo $failure
}

function warmup_td() {
    echo 1
}

function run_td() {
    local result_file="$2"
    local log_base_dir="$3"

    IFS='|' read -r -a progs <<< "$1"

    local server_log="$log_base_dir/server.log"

    local run_log="$log_base_dir/run.log"

    # Start the TD Server
    ${TD_SERVER} 1>"$server_log" 2>&1 &
    local server_pid=$!

    echo "Started TD Server ($server_pid)" >> "$run_log"

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
                ${BINDIR}/${name} td 1>"$prog_log" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                LD_PRELOAD=${TD_LIB} ${BINDIR}/${name} ${args} 1>"$prog_log" 2>&1
            else
                LD_PRELOAD=${TD_LIB} ${BINDIR}/${name} 1>"$prog_log" 2>&1
            fi

            echo "total_ms: $(time_diff $prog_start)" >> "$prog_log"
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

    if ps -p $server_pid > /dev/null; then
        # Exit the server
        kill $server_pid
    else
        # Something went wrong and we need to retry …
        echo "The server did not finish successfully" >> "$run_log"
        all_finished=0
    fi

    if [ $all_finished -eq 1 ]; then
        echo "td;$total_t;$total_e" >> $result_file
        echo 1
    else
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}
