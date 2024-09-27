#!/usr/bin/env bash

export SCRIPTDIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Include our support libraries
source "$SCRIPTDIR/utils/continuation.inc.sh"
source "$SCRIPTDIR/utils/logging.inc.sh"
source "$SCRIPTDIR/utils/printing.inc.sh"

printf "E-Mapper Benchmark Suite\n -- Prepare Script --\n\n"

if [ ! -e "${SCRIPTDIR}/config.inc.sh" ]; then
    printf "Missing config file 'config.inc.sh'!\n"
    exit 1;
fi

printf "Sourcing the main configuration file\n"

source "$SCRIPTDIR/config.inc.sh"

# Prepare the environment for our measurements
printf "Setting up the environment\n"
printf " - Allowing access to perf "
echo 0 > /proc/sys/kernel/perf_event_paranoid
if [ $? -ne 0 ]; then
    printf "Failure!\n"
    exit 1;
else
    printf "Done\n"
fi

printf " - Platform specific setup "
success=$(${platform_routines[setup]})
if [ $success -ne 0 ]; then
    printf "Failure!\n"
    exit 1
else
    printf "Done\n"
fi

printf "All Done!\n"
