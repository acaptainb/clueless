#!/bin/sh
# Start (or stop) the two Bonsai servers: 9B answerer on 8080, 4B watcher on 8082. Localhost only; works with Wi-Fi off.
#   ./scripts/servers.sh start | stop | status              both servers
#   ./scripts/servers.sh start answerer | start watcher     one server, leaving the other alone
#   ./scripts/servers.sh stop answerer | stop watcher
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${LLAMA_SERVER:-$ROOT/vendor/llama.cpp/build-mac/bin/llama-server}"
M="$ROOT/models/bonsai"
RUN="$ROOT/.run"; mkdir -p "$RUN"

port_of() { case "$1" in answerer) echo 8080;; watcher) echo 8082;; esac; }

# Is the process named in this server's pid file still there?
alive() { [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }

# The pid of the llama-server listening on this server's port, if there is one. It is found from the port,
# so it works when the pid file is missing or names another process. Prints nothing where lsof is missing.
listener() {
  for cand in $(lsof -nP -iTCP:"$(port_of "$1")" -sTCP:LISTEN -t 2>/dev/null); do
    case "$(ps -p "$cand" -o comm= 2>/dev/null)" in *llama-server*) echo "$cand"; return 0;; esac
  done
}

# Does anything answer on this server's port? Also true while the model is still loading (HTTP 503).
answering() { curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$(port_of "$1")/health"; }

# True if this server is already up or coming up, so it must not be launched a second time. A second
# copy cannot take the port and exits, but its pid would replace the running server's in the pid file,
# and `stop` could no longer find the one that is running. A pid file that was lost that way is put right here.
running() {
  alive "$1" && return 0
  found="$(listener "$1")"
  if [ -n "$found" ]; then echo "$found" > "$RUN/$1.pid"; return 0; fi
  answering "$1"
}

# Stop one server: the process in its pid file, and a llama-server that holds its port without being in
# the pid file. Then wait (5 s at most) until the port is free, so a new one can be started right away.
stop_one() {
  [ -f "$RUN/$1.pid" ] && kill "$(cat "$RUN/$1.pid")" 2>/dev/null
  rm -f "$RUN/$1.pid"
  found="$(listener "$1")"
  [ -n "$found" ] && kill "$found" 2>/dev/null
  n=0; while [ -n "$(listener "$1")" ] && [ $n -lt 25 ]; do sleep 0.2; n=$((n+1)); done
  return 0
}

# Launch one server in the background. Does not wait for it to be ready.
launch() {
  case "$1" in
    answerer)
      # 9B answerer, with vision projector. The MTP file + draft-mtp speculation measured ~1.5x faster
      # than plain PQ2_0 with identical answers on our test set (see BENCHMARKS.md).
      # --cache-ram 0 turns off the server's host-side prompt cache. Its default is 8 GB, and after about
      # 30 minutes of use the answerer had grown from 2 GB to 10 GB. Off, it stays near 1.6 GB and the first
      # token comes about 0.1 s later (BENCHMARKS.md). ANSWERER_CACHE_RAM=<MiB> turns it back on.
      nohup "$BIN" -m "$M/Ternary-Bonsai-2-9B-PQ2_0-MTP-Q8_0.gguf" --mmproj "$M/Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf" \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        ${ANSWERER_IMAGE_MAX_TOKENS:+--image-max-tokens "$ANSWERER_IMAGE_MAX_TOKENS"} \
        --cache-ram "${ANSWERER_CACHE_RAM:-0}" \
        -ngl 99 -fa on -c "${ANSWERER_CTX:-8192}" -np 1 --host 127.0.0.1 --port 8080 --offline \
        > "$RUN/answerer.log" 2>&1 & echo $! > "$RUN/answerer.pid" ;;
    watcher)
      # Watcher, text only. 4B by default: 16/16 on our watcher test set vs 13-14/16 for 2B (see BENCHMARKS.md).
      # WATCHER_MODEL=2B halves the latency (0.5s vs 1.0s) at lower accuracy.
      nohup "$BIN" -m "$M/Ternary-Bonsai-2-${WATCHER_MODEL:-4B}-PQ2_0.gguf" \
        -ngl 99 -fa on -c "${WATCHER_CTX:-4096}" -np 1 --host 127.0.0.1 --port 8082 --offline \
        > "$RUN/watcher.log" 2>&1 & echo $! > "$RUN/watcher.pid" ;;
  esac
}

wait_ready() {
  p="$(port_of "$1")"; i=0
  until curl -sf "http://127.0.0.1:$p/health" >/dev/null; do
    i=$((i+1)); [ $i -gt 120 ] && { echo "port $p did not come up; see $RUN/$1.log"; exit 1; }; sleep 0.5
  done; echo "port $p ready"
}

# With a name: restart just that server (the old one is stopped first, so the port is free).
# Without: launch whichever of the two is not running yet, then wait for both. A server that is already
# up is left alone (check.sh and the app call this when only one of them is down).
start() {
  case "$1" in
    answerer|watcher) stop_one "$1"; launch "$1"; wait_ready "$1" ;;
    "") for s in answerer watcher; do
          if running "$s"; then echo "$s is already running on port $(port_of "$s"): left alone"; else launch "$s"; fi
        done
        wait_ready answerer; wait_ready watcher ;;
    *) usage ;;
  esac
}
stop() {
  case "$1" in
    answerer|watcher) stop_one "$1" ;;
    "") stop_one answerer; stop_one watcher ;;
    *) usage ;;
  esac
}
status() { for p in 8080 8082; do printf "%s: " $p; curl -s "http://127.0.0.1:$p/health" || echo down; echo; done; }
usage() { echo "usage: $0 start|stop [answerer|watcher] | status"; exit 2; }
case "$1" in start) start "$2";; stop) stop "$2";; status) status;; *) usage;; esac
