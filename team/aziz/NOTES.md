# Aziz's notes

Personal handoff notes for Aziz's next session (and for Aziz's coding agent). Only Aziz edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

Nothing in hand. Next engine tasks by payoff: T08 (screenshot cost), T09 (prompt cache reuse), then T13 to T15 for call mode.

## Pushed, waiting for a Mac mini test

- `aziz/prompts-data` (T26). Never compiled. Likeliest build errors: `Sources/CluelessCore/Prompts.swift` (new file) and the `loadCases` generic in `Sources/clueless-bench/main.swift`. If the bench says BUILT-IN, `Prompts.dataRoot` (`#filePath`) is pointing at the wrong folder.

## Ideas and things to remember

- This Windows laptop has no Swift and no Python; Node is installed. Git name and email were unset here and are now set for this repo only.
- After T26 merges, prompt experiments for T08 and T09 are edits to `prompts/*.txt` and `bench/*.json`: no Swift needed from this laptop.
- `scripts/servers.sh start answerer` / `start watcher` (start one server alone) was asked for by Yusuf in the work log for T16; not done.
