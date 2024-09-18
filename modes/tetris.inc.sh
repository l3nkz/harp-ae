source "${SCRIPTDIR}/modes/tetris_base.inc.sh"

function check_tetris() {
    __check_tetris
}

function warmup_tetris() {
    local log_base_dir="$2"
    local trace_base_dir="$3"
    local learn_dir="$4"

    local warmup_log="${log_base_dir}/warmup.log"

    IFS='|' read -r -a progs <<< "$1"

    success=0
    run=0
    while [ $success -ne 1 ]; do
        local server_log="$log_base_dir/server-${run}.log"
        local trace_log="$trace_base_dir/trace-${run}.json"

        # Start the TETRiS server
        ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$trace_log" -s "$learn_dir" $TETRIS_SERVER_EXTRA_ARGS 1>"$server_log" 2>&1 &
        local server_pid=$!

        # Start the learn loops for the individual applications
        for p in ${progs[@]}; do
            log_dir="${log_base_dir}/$(save_name $p)-${run}"
            learn_log="${log_base_dir}/learning_$(save_name $p).log"

            mkdir -p "$log_dir"

            __warmup_prog_tetris $p "$log_dir" "$server_log" "$server_pid" 1>>"$learn_log" 2>&1
        done

        # Check if the learning worked for all applications
        if ps -p $server_pid > /dev/null; then
            # Exit the server and store the result
            kill -s SIGUSR1 $server_pid
            sleep 1
            kill $server_pid

            success=1
        else
            echo "Server did not exit successfully! Restart learning" >> ${warmup_log}
            success=0
        fi

        for p in ${progs[@]}; do
            last_stage=$(tail -1 "${log_base_dir}/learning_$(save_name $p).log")

            if [ "x$last_stage" != "xMature" ]; then
                success=0
                echo "$(save_name $p) did not finish learning!" >> ${warmup_log}
            else
                learn_runs=$(cat "${log_base_dir}/learning_$(save_name $p).log" | wc -l)
                echo "$(save_name $p) fully warmed up after ${learn_runs} run(s)" >> ${warmup_log}
            fi
        done

        # Remove leftover files
        rm -f /tmp/tetris_*

        run=$((run + 1))
    done

    echo $success
}

function run_tetris() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"
    local learn_dir="$5"

    IFS='|' read -r -a progs <<< "$1"

    local server_log="$log_base_dir/server.log"
    local trace_log="$trace_base_dir/trace.json"

    local run_log="$log_base_dir/run.log"

    # Start the TETRiS server
    ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$trace_log" -s "$learn_dir" $TETRIS_SERVER_EXTRA_ARGS 1>"$server_log" 2>&1 &
    local server_pid=$!

    echo "Started TETRiS Server ($server_pid)" >> "$run_log"

    local begin_t=$(get_time)
    local begin_e=$(get_energy)

    # Start the individual programs
    declare -a prog_pids
    for p in ${progs[@]}; do
        (
            local name=$(save_name $p)
            export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/empty.yaml"

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
        echo "tetris;$total_t;$total_e" >> $result_file
        echo 1
    else
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}
