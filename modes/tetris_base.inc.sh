if [ -n "$tetris_base_sourced" ]; then return fi

tetris_base_sourced=1

export TETRIS_SERVER="${SCRIPTDIR}/bin/tetrisserver"
export TETRIS_LIB="${SCRIPTDIR}/lib/libtetrisclientlegacy.so"

function __check_tetris() {
    local failure=0
    if [ ! -x "$TETRIS_SERVER" ]; then
        failure=1
    fi
    if [ ! -e "$TETRIS_LIB" ]; then
        failure=1
    fi

    echo $failure
}

function __warmup_prog_tetris() {
    local prog="$1"
    local log_base_dir="$2"
    local server_log="$3"
    local server_pid=$4
    local mode=${5:-tetris}

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
            ${BINDIR}/${name} $mode 1>"$prog_log" 2>&1
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
