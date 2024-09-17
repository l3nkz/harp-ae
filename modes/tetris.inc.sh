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
    local server_log="$3"
    local server_pid=$4

    local stage="Initial"
    local run=0
    local stable_run=0
    local repeat=1

    while [ $repeat -eq 1 ]; do
        # Before starting the app check if the server is still running
        ps -p $server_pid > /dev/null
        if [ $? -ne 0 ]; then
            break
        fi

        # Start the application
        local begin_t=$(get_time)
        local begin_e=$(get_energy)

        export TETRIS_MAPPING="${TETRIS_MAPPING_BASE}/empty.yaml"
        local name=$(save_name $p)
        local prog_log="$log_base_dir/${name}-${run}.log"

        if [[ "$p" == !* ]]; then
            ${BINDIR}/${name} tetris 1>"$prog_log" 2>&1
        elif [[ "$p" == \?* ]]; then
            args=$(cat ${BINDIR}/${name}.args)
            LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} ${args} 1>"$prog_log" 2>&1
        else
            LD_PRELOAD=${TETRIS_LIB} ${BINDIR}/${name} 1>"$prog_log" 2>&1
        fi

        # Extract the stage of the last run
        stage=$(cat $server_log | grep "client registered" | grep $name | sed "s/.*(Stage \(.*\))/\1/" | tail -1)

        echo "Detected Stage: $stage" >> "$prog_log"
        echo "Run: $run" >> "$prog_log"

        echo "$stage"

        # Check if we are done with warm up
        if [ $stage == "Mature" ]; then
            if [ $stable_run -eq 2 ]; then
                repeat=0
            else
                # If we are in "Mature" stage still make two additional runs
                stable_run=$((stable_run + 1))
                repeat=1
            fi
        else
            # Repeat until stage is "Mature"
            repeat=1
        fi

        run=$((run + 1))
    done
}

function warmup_tetris() {
    local log_base_dir="$2"
    local trace_base_dir="$3"
    local learn_dir="$4"

    IFS='|' read -r -a progs <<< "$1"

    success=0
    run=0
    while [ success -ne 1 ]; do
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

            __warmup_prog $p "$log_dir" "$server_log" "$server_pid" 1>>"$learn_log" 2>&1
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
                learn_runs=$(wc -l "${log_base_dir}/learning_$(save_name $p).log")
                echo "$(save_name $p) fully warmed up after ${learn_rnus} run(s)" >> ${warmup_log}
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
        exit_code=$(wait $p)
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
