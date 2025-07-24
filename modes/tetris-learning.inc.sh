source "${SCRIPTDIR}/modes/tetris_base.inc.sh"

function check_tetris-learning() {
    __check_tetris
}

function __learn_prog() {
    local prog="$1"
    local log_base_dir="$2"
    local server_log="$3"
    local server_pid=$4
    local step="$5"
    local start=$6

    local stage="Initial"
    local run=0
    local repeat=1

    while [ $repeat -eq 1 ]; do
        # Before starting the app check if the server is still running
        ps -p $server_pid > /dev/null
        if [ $? -ne 0 ]; then
            break
        fi

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

        # Check if we are done with learning
	local learn_time=$(time_diff $start)
        if [ $step -eq 1 -a "x$stage" == "xMature" ]; then
	    repeat=0
	elif [ $step -eq 2 -a $learn_time -ge 100000 ]; then
	    repeat=0
        else
            repeat=1
        fi

        run=$((run + 1))
    done
}

function warmup_tetris-learning() {
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
        local start=$(get_time)

        # Start the TETRiS server
        ${TETRIS_SERVER} -p $TETRIS_PLATFORM -t "$trace_log" -s "$learn_dir" $TETRIS_SERVER_EXTRA_ARGS 1>"$server_log" 2>&1 &
        local server_pid=$!

        # Start the learn loops for the individual applications in parallel
	    echo "Learning step 1" >> $warmup_log
        declare -a prog_pids
        for p in ${progs[@]}; do
            log_dir="${log_base_dir}/$(save_name $p)_1-${run}"
            learn_log="${log_base_dir}/learning_$(save_name $p)_1.log"

            mkdir -p "$log_dir"

            (
                __learn_prog $p "$log_dir" "$server_log" "$server_pid" "1" "$start"
            ) 1>>"$learn_log" 2>&1 &
            prog_pids+=("$!")
        done

        # Take snapshots of the learning every 5 seconds
        (
            sec=0
            while /usr/bin/true; do
                if ps -p $server_pid > /dev/null; then
                    mkdir -p "$learn_dir/$sec"
                    kill -s SIGUSR2 $server_pid
                    sleep 0.2
                    cp "$learn_dir"/*.yaml "$learn_dir/$sec" 2>/dev/null
                    sec=$((sec + 5))
                    sleep 4.8
                fi
            done
        ) &
        local copy_pid=$!

        # Wait for the programs to learn and finish
        for p in ${prog_pids[@]}; do
            wait $p
        done

        # Check if the server is still running and if we need to continue
        # learning to fill our learn time
        learn_time=$(time_diff $start)
        if ps -p $server_pid > /dev/null; then
            if [ $learn_time -lt 100000 ]; then
                # continue learning to show that it can improve
                echo "Learning step 2" >> $warmup_log

                prog_pids=()
                for p in ${progs[@]}; do
                    log_dir="${log_base_dir}/$(save_name $p)_2-${run}"
                    learn_log="${log_base_dir}/learning_$(save_name $p)_2.log"

                    mkdir -p "$log_dir"

                    (
                        __learn_prog $p "$log_dir" "$server_log" "$server_pid" "2" "$start"
                    ) 1>>"$learn_log" 2>&1 &
                    prog_pids+=("$!")
                done

                # Wait for the programs to learn and finish
                for p in ${prog_pids[@]}; do
                    wait $p
                done
            else
                echo "No step 2, because learning time > 100s ($learn_time)" >> $warmup_log
            fi
        fi

	    kill $copy_pid

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
            last_stage=$(tail -1 "${log_base_dir}/learning_$(save_name $p)_1.log")

            if [ "x$last_stage" != "xMature" ]; then
                success=0
                echo "$(save_name $p) did not finish learning!" >> "${warmup_log}"
            else
                learn_runs=$(cat "${log_base_dir}/learning_$(save_name $p)_1.log" | wc -l)
                echo "$(save_name $p) fully warmed up after ${learn_runs} run(s)" >> ${warmup_log}
            fi
        done

        # Remove leftover files
        rm -f /tmp/tetris_*

        if [ $success -eq 0 ]; then
	    # clean up old learning states and retry
	    rm -rf "$learn_dir"/*
	fi

        run=$((run + 1))
    done

    echo $success
}

function __run_tetris-learning() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"
    local learn_dir="$5"
    local iteration="$6"

    mkdir -p "$log_base_dir"
    mkdir -p "$trace_base_dir"

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
        stages=$(grep "registered" "$server_log" | sed "s/.*(Stage \(.*\)).*/\1/" | paste -s -d_)
        echo "$iteration;$total_t;$total_e;$stages" >> $result_file
        echo 1
    else
        echo 0
    fi

    # Remove leftover files
    rm -f /tmp/tetris_*
}

function run_tetris-learning() {
    local result_file="$2"
    local log_base_dir="$3"
    local trace_base_dir="$4"
    local learn_dir="$5"

    local this_learn_dir="$learn_dir/now"
    mkdir -p "$this_learn_dir"

    for cur in $(seq 0 5 100); do
    success=0
    while [ $success -ne 1 ]; do
        printf "${cur} "
        if [ -e "$learn_dir/$cur" ]; then
            for f in "$learn_dir/$cur/"*; do
                if [ -e "$f" ]; then
                    cp "$f" "$this_learn_dir"
                fi
            done
        fi

        success=$(__run_tetris-learning "$1" "$result_file" "$log_base_dir/${cur}" "$trace_base_dir/${cur}" "$this_learn_dir" "${cur}")

        if [ $success -ne 1 ]; then
            printf "!! "
        fi
            rm -f "$this_learn_dir"/*
        done
    done
}
