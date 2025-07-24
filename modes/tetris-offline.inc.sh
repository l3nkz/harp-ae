source "${SCRIPTDIR}/modes/tetris_base.inc.sh"

function check_tetris-offline() {
    __check_tetris
}

function warmup_tetris-offline() {
    echo 1
}

function run_tetris-offline() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"

    IFS='|' read -r -a progs <<< "$1"

    local server_log="$log_base_dir/server.log"
    local trace_log="$trace_base_dir/trace.json"

    local run_log="$log_base_dir/run.log"

    # Start the TETRiS server
    ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$trace_log" $TETRIS_SERVER_EXTRA_ARGS --no-measure 1>"$server_log" 2>&1 &
    local server_pid=$!

    echo "Started TETRiS Server ($server_pid)" >> "$run_log"

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)
            export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/${name}.yaml"

            local prog_log="$log_base_dir/${name}.log"
            local prog_start=$(get_time)

            if [[ "$p" == !* ]]; then
                ${BINDIR}/${name} tetris 1>"$prog_log" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} ${args} 1>"$prog_log" 2>&1
            else
                LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} 1>"$prog_log" 2>&1
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

    # Check if everything worked out great and we can continue with the next iteration
    if ps -p $server_pid > /dev/null; then
        # Save the trace and exit the server
        kill -s SIGUSR1 $server_pid
        sleep 1
        kill $server_pid
    else
        # Something went wrong and we need to retry …
        echo "The server did not finish successfully" >> "$run_log"
        all_finished=0
    fi

    if [ $all_finished -eq 1 ]; then
        echo "tetris-offline;$total_t;$total_e" >> $result_file
        echo 1
    else
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}
