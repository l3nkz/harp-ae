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

    local serverlog="$log_base_dir/server.log"
    ${TD_SERVER} 1>"$serverlog" 2>&1 &
    local server_pid=$!

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
                ${BINDIR}/${name} td 1>"$proglog" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                LD_PRELOAD=${TD_LIB} ${BINDIR}/${name} ${args} 1>"$proglog" 2>&1
            else
                LD_PRELOAD=${TD_LIB} ${BINDIR}/${name} 1>"$proglog" 2>&1
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

    if ps -p $server_pid > /dev/null; then
        # Exit the server and store the result
        kill $server_pid

        echo "td;$total_t;$total_e" >> $result_file
        echo 1
    else
        # Something went wrong and we need to retry …
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}
