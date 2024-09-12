export TETRIS_SERVER="${SCRIPTDIR}/bin/tetrisserver"
export TETRIS_LIB="${SCRIPTDIR}/lib/libtetrisclientlegacy.so"

function check_tetris() {
    local failure=0
    if [ ! -x "$TETRIS_SERVER" ]; then
        failure=1
    fi
    if [ ! -e "$TETRIS_LIB" ]; then
        failure=1
    fi

    echo $failure
}

function __warmup_prog() {
    local prog="$1"
    local log_base_dir="$2"
    local trace_base_dir="$3"
    local learn_dir="$4"

    local stage="Initial"
    local run=0
    while [ $stage !=  "Stable" ]; do
        local serverlog="$log_base_dir/server-${run}.log"
        local tracelog="$trace_base_dir/trace-${run}.json"

        # Start the TETRiS server
        ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$tracelog" -s "$learn_dir" 1>"$serverlog" 2>&1 &
        local server_pid=$!

        # Start the application

        local begin_t=$(get_time)
        local begin_e=$(get_energy)

        export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/empty.yaml"
        local name=$(save_name $p)
        local proglog="$log_base_dir/${name}-${run}.log"

        if [[ "$p" == !* ]]; then
            ${BINDIR}/${name} tetris 1>"$proglog" 2>&1
        elif [[ "$p" == \?* ]]; then
            args=$(cat ${BINDIR}/${name}.args)
            LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} ${args} 1>"$proglog" 2>&1
        else
            LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} 1>"$proglog" 2>&1
        fi

        # Check if everything worked out great and we can continue with the next iteration
        if ps -p $server_pid > /dev/null; then
            # Exit the server and store the result
            kill -s SIGUSR1 $server_pid
            sleep 1
            kill $server_pid

            # Extract the stage
            stage=$(cat $serverlog | grep "client registered" | sed "s/.*(Stage \(.*\))/\1/")
            run=$((run + 1))

            echo "Detected Stage: $stage" >> "$proglog"
            echo "Run: $run" >> "$proglog"
        fi
    done

    echo 1

    # Remove leftover files
    rm -f /tmp/tetris_*

}

function warmup_tetris() {
    local log_base_dir="$2"
    local trace_base_dir="$3"
    local learn_dir="$4"

    IFS='|' read -r -a progs <<< "$1"

    success=0
    for p in ${progs[@]}; do
        log_dir="${log_base_dir}/$(save_name $p)"
        trace_dir="${trace_base_dir}/$(save_name $p)"

        mkdir -p "$log_dir"
        mkdir -p "$trace_dir"

        success=$(__warmup_prog $p "$log_dir" "$trace_dir" "$learn_dir")
        if [ $success -ne 1 ]; then
            break
        fi
    done

    echo $success
}

function run_tetris() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"
    local learn_dir="$5"

    IFS='|' read -r -a progs <<< "$1"

    local serverlog="$log_base_dir/server.log"
    local tracelog="$trace_base_dir/trace.json"

    # Start the TETRiS server
    ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$tracelog" -s "$learn_dir" 1>"$serverlog" 2>&1 &
    local server_pid=$!

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)
            export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/empty.yaml"

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

        echo "tetris;$total_t;$total_e" >> $result_file
        echo 1
    else
        # Something went wrong and we need to retry …
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*

}
