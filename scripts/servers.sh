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

# Stop one server by its pid file, if it is running.
stop_one() {
  [ -f "$RUN/$1.pid" ] && kill "$(cat "$RUN/$1.pid")" 2>/dev/null
  rm -f "$RUN/$1.pid"
}

# Launch one server in the background. Does not wait for it to be ready.
launch() {
  case "$1" in
    answerer)
      # 9B answerer, with vision projector. The MTP file + draft-mtp speculation measured ~1.5x faster
      # than plain PQ2_0 with identical answers on our test set (see BENCHMARKS.md).
      nohup "$BIN" -m "$M/Ternary-Bonsai-2-9B-PQ2_0-MTP-Q8_0.gguf" --mmproj "$M/Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf" \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        ${ANSWERER_IMAGE_MAX_TOKENS:+--image-max-tokens "$ANSWERER_IMAGE_MAX_TOKENS"} \
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
# Without: launch both, as before, then wait for both.
start() {
  case "$1" in
    answerer|watcher) stop_one "$1"; launch "$1"; wait_ready "$1" ;;
    "") launch answerer; launch watcher; wait_ready answerer; wait_ready watcher ;;
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
