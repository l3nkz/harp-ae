export TETRIS_SERVER="${SCRIPTDIR}/bin/tetrisserver"
export TETRIS_LIB="${SCRIPTDIR}/lib/libtetrisclientlegacy.so"

function check_tetris-offline() {
    local failure=0
    if [ ! -x "$TETRIS_SERVER" ]; then
        failure=1
    fi
    if [ ! -e "$TETRIS_LIB" ]; then
        failure=1
    fi

    echo $failure
}

function warmup_tetris-offline() {
    echo 1
}

function run_tetris-offline() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"

    IFS='|' read -r -a progs <<< "$1"

    local serverlog="$log_base_dir/server.log"
    local tracelog="$trace_base_dir/trace.json"

    # Start the TETRiS server
    ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$tracelog" --no-measure $TETRIS_SERVER_EXTRA_ARGS 1>"$serverlog" 2>&1 &
    local server_pid=$!

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)
            export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/${name}.yaml"

            local proglog="$log_base_dir/${name}.log"
            local prog_start=$(get_time)

            if [[ "$p" == !* ]]; then
                ${BINDIR}/${name} tetris 1>"$proglog" 2>&1
            elif [[ "$p" == \?* ]]; then
                args=$(cat ${BINDIR}/${name}.args)
                LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} ${args} 1>"$proglog" 2>&1
            else
                LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} 1>"$proglog" 2>&1
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

    # Check if everything worked out great and we can continue with the next iteration
    if ps -p $server_pid > /dev/null; then
        # Exit the server and store the result
        kill -s SIGUSR1 $server_pid
        sleep 1
        kill $server_pid

        echo "tetris-offline;$total_t;$total_e" >> $result_file
        echo 1
    else
        # Something went wrong and we need to retry …
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}
