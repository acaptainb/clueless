#!/bin/sh
# Start (or stop) the two Bonsai servers: 9B answerer on 8080, 4B watcher on 8082. Localhost only; works with Wi-Fi off.
#   ./scripts/servers.sh start | stop | status
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${LLAMA_SERVER:-$ROOT/vendor/llama.cpp/build-mac/bin/llama-server}"
M="$ROOT/models/bonsai"
RUN="$ROOT/.run"; mkdir -p "$RUN"

start() {
  # 9B answerer, with vision projector. The MTP file + draft-mtp speculation measured ~1.5x faster
  # than plain PQ2_0 with identical answers on our test set (see BENCHMARKS.md).
  nohup "$BIN" -m "$M/Ternary-Bonsai-2-9B-PQ2_0-MTP-Q8_0.gguf" --mmproj "$M/Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf" \
    --spec-type draft-mtp --spec-draft-n-max 2 \
    ${ANSWERER_IMAGE_MAX_TOKENS:+--image-max-tokens "$ANSWERER_IMAGE_MAX_TOKENS"} \
    -ngl 99 -fa on -c "${ANSWERER_CTX:-8192}" -np 1 --host 127.0.0.1 --port 8080 --offline \
    > "$RUN/answerer.log" 2>&1 & echo $! > "$RUN/answerer.pid"
  # Watcher, text only. 4B by default: 16/16 on our watcher test set vs 13-14/16 for 2B (see BENCHMARKS.md).
  # WATCHER_MODEL=2B halves the latency (0.5s vs 1.0s) at lower accuracy.
  nohup "$BIN" -m "$M/Ternary-Bonsai-2-${WATCHER_MODEL:-4B}-PQ2_0.gguf" \
    -ngl 99 -fa on -c "${WATCHER_CTX:-4096}" -np 1 --host 127.0.0.1 --port 8082 --offline \
    > "$RUN/watcher.log" 2>&1 & echo $! > "$RUN/watcher.pid"
  for p in 8080 8082; do
    i=0; until curl -sf "http://127.0.0.1:$p/health" >/dev/null; do
      i=$((i+1)); [ $i -gt 120 ] && { echo "port $p did not come up; see $RUN/*.log"; exit 1; }; sleep 0.5
    done; echo "port $p ready"
  done
}
stop() { for n in answerer watcher; do [ -f "$RUN/$n.pid" ] && kill "$(cat "$RUN/$n.pid")" 2>/dev/null; rm -f "$RUN/$n.pid"; done; }
status() { for p in 8080 8082; do printf "%s: " $p; curl -s "http://127.0.0.1:$p/health" || echo down; echo; done; }
case "$1" in start) start;; stop) stop;; status) status;; *) echo "usage: $0 start|stop|status"; exit 2;; esac
