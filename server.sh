#!/usr/bin/env bash
# Runs the BeamMP server in the foreground from DATA_DIR: console commands on stdin, output on
# stdout. The entrypoint of the image, and the command of the server manager's entrypoint.
#
# BeamMP can't be given the console directly when it isn't a terminal (Docker, the manager's FIFO):
# - after `exit` it shuts down, then waits for its console thread, stuck reading stdin until EOF.
#   With stdin held open (the manager's FIFO is), it never exits.
# - SIGTERM kills it without the graceful shutdown.
# So the server reads its own pipe, which this script feeds from stdin and closes once the server
# logged its shutdown, and SIGTERM/SIGINT become an `exit` command.
set -euo pipefail

cd "${DATA_DIR:-/beammp}"

console=$(mktemp -u /tmp/beammp-console.XXXXXX)
mkfifo -m 600 "$console"
# Held open so the server never reads an EOF between two commands
exec 4<>"$console"

# The server's output, printed as is. Signals this script once it logged the end of its shutdown.
watch_output() {
    local line
    while IFS= read -r line; do
        printf '%s\n' "$line"
        if [[ $line == *'[INFO] Shutdown.'* ]]; then
            kill -USR1 $$
        fi
    done
}
# A real close: `watch_output 4>&-` would only hide fd 4, bash keeps a copy to restore it after
exec 5> >(exec 4>&-; watch_output)
watcher=$!

# Console input to the server. The explicit <&0 is needed: bash otherwise gives background jobs
# /dev/null as stdin.
cat <&0 >&4 4>&- 5>&- &
forward=$!

# Read only: once this script and cat close their ends, the server reads an EOF
/opt/beammp/BeamMP-Server "$@" <"$console" >&5 2>&1 4>&- 5>&- &
server=$!
rm -f "$console"

closed=false
close_console() {
    if [[ $closed == false ]]; then
        closed=true
        kill "$forward" 2>/dev/null || true
        exec 4>&-
    fi
}
trap close_console USR1
trap 'echo "Received stop signal, stopping server..."; echo exit >&4 2>/dev/null || true' TERM INT

# `wait` returns early when a trapped signal arrives, so keep waiting until the server exits
status=0
while kill -0 "$server" 2>/dev/null; do
    if wait "$server"; then status=0; else status=$?; fi
done
close_console

# Let the last lines of output through
exec 5>&-
wait "$watcher" 2>/dev/null || true
exit "$status"
