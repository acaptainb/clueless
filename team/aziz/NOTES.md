# Aziz's notes

Personal handoff notes for Aziz's next session (and for Aziz's coding agent). Only Aziz edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

T08 is written and waiting for the Mac mini (below). Next engine tasks by payoff: T09 (prompt cache reuse), then T13 to T15 for call mode.

## Pushed, waiting for a Mac mini test

- `aziz/prompts-data` (T26). Never compiled. Likeliest build errors: `Sources/CluelessCore/Prompts.swift` (new file) and the `loadCases` generic in `Sources/clueless-bench/main.swift`. If the bench says BUILT-IN, `Prompts.dataRoot` (`#filePath`) is pointing at the wrong folder.
- `aziz/screenshot-cost` (T08 engine) and `aziz/screenshot-cost-app` (T08 app wiring, stacked on it). Never compiled. Likeliest build errors: the tuple array `variants` and the trailing closure `{ _ in }` in `Sources/clueless-bench/ScreenCost.swift`; `Task.detached` capturing `shot` in `AppState.run`. After the bench: set `ScreenPolicy.imageMaxSide` to the smallest size that keeps `both` at 6/6, write the table into BENCHMARKS.md, then move T08 to Done in the PR. If `auto` misses a question, add its word to `visualStems` in `ScreenInput.swift`.
- Two sessions shared this laptop checkout on Sat night: T08 was written in the git worktree `.worktrees/t08`, T26 in the main folder.

- `aziz/demo-assets` (T21). The audio script (`scripts/make_demo_assets.py`) has never run: likeliest problems are the `say -v ?` voice-list parsing and missing voices. Page 2 of the PDF was only seen as a thumbnail. T04 (answer quality) uses `demo/*/questions.json` once the audio exists.
- `aziz/servers-one` is the tip of a stack: `aziz/prompt-cache` (T09), `aziz/word-cut` (T19), `aziz/call-notes` (T13 to T15), `aziz/test-set` (T10), `aziz/servers-one` (T27), with `main` merged in. Never compiled. One `check.sh aziz/servers-one` tests all of it; `clueless-bench selftest` checks the logic with no servers. Riskiest: the SpeakerKit calls in `Speakers.swift` (written from the SDK source at 1.1.1) and the new prompt order (`CLUELESS_PROMPT_LAYOUT=classic` reverts it without a rebuild).
- Still open after that: T04 (needs the Mac mini and T21 assets), the real-audio half of T10, and wiring `SessionNotes.make` and `SessionAudio` into `AppState.swift` (asked of Yusuf in the work log).
- The laptop clock is Pacific and `TZ=America/New_York date` prints UTC in Git Bash. Eastern time = laptop time + 3 hours.

- Mac mini queue for my part, in order (Sat 7:10 pm): 1 measure T26/T08 on `main`; 2 `aziz/demo-assets` (T21); 3 `aziz/servers-one` = PR #8 (T09, T19, T13 to T15, T10, T27); 4 T04 on `main`. PRs #9, #10, #11 were closed in favour of #8.

## Ideas and things to remember

- This Windows laptop has no Swift and no Python; Node is installed. Git name and email were unset here and are now set for this repo only.
- After T26 merges, prompt experiments for T08 and T09 are edits to `prompts/*.txt` and `bench/*.json`: no Swift needed from this laptop.
- `scripts/servers.sh start answerer` / `start watcher` (start one server alone) was asked for by Yusuf in the work log for T16; not done.
