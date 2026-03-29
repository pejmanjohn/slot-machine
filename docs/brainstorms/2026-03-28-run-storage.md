---
date: 2026-03-28
topic: run-storage
---

# Run Storage: Persist All Slot Machine Artifacts

## What We're Building

Replace temp directories with a permanent, project-local `.slot-machine/runs/` directory that keeps all artifacts from every run. Nothing is throwaway.

## Key Decisions

- **Keep everything by default.** Files are tiny (~50KB per full run). No cleanup, no TTL, no retention policy.
- **`.slot-machine/` in project root.** Dotdir, out of the way. Add to `.gitignore` on first run.
- **Date-prefixed run folders.** Chronological browsing, feature name in the slug.
- **No temp directories.** Slots write directly to the run folder. Nothing uses `mktemp`.

## Structure

```
.slot-machine/
└── runs/
    └── 2026-03-28-vc-rejection/
        ├── slot-1.md          # Slot 1 draft/implementation
        ├── slot-2.md          # Slot 2 draft/implementation
        ├── slot-3.md          # Slot 3 draft/implementation
        ├── review-1.md        # Slot 1 scorecard
        ├── review-2.md        # Slot 2 scorecard
        ├── review-3.md        # Slot 3 scorecard
        ├── verdict.md         # Judge verdict + full reasoning
        └── output.md          # Final winner or synthesis
```

For coding runs, `slot-{i}.diff` instead of `slot-{i}.md` (git diff output from the worktree, much smaller than copying all files).

## Orchestrator Behavior

Phase 1 (Setup):
1. Create `.slot-machine/runs/{date}-{feature-slug}/`
2. If `.slot-machine/` not in `.gitignore`, add it

Phase 2 (Implementation):
- File isolation: slots write to `{run_dir}/slot-{i}.md` instead of temp dir
- Worktree isolation: after each slot completes, save `git diff` to `{run_dir}/slot-{i}.diff`

Phase 3 (Review):
- Save each reviewer's full scorecard to `{run_dir}/review-{i}.md`
- Save judge's full verdict to `{run_dir}/verdict.md`

Phase 4 (Resolution):
- Save final output to `{run_dir}/output.md`
- For coding: also save the merge commit SHA in verdict.md

Final Report:
- Reference `{run_dir}/output.md` as the output path
- For long outputs (>60 lines), the excerpt points to this real path

## What This Replaces

- `mktemp -d` for file isolation → `{run_dir}/` directly
- Lost reviewer scorecards → saved to `review-{i}.md`
- Lost judge reasoning → saved to `verdict.md`
- Ugly temp paths in user output → clean `.slot-machine/runs/...` paths

## Impact on SKILL.md

- Phase 1: Add run directory creation + .gitignore step
- Phase 2: Change file isolation paths from temp dir to run dir
- Phase 3: Add scorecard/verdict saving after each agent returns
- Phase 4: Change final output path to run dir
- Final Report: Reference run dir paths

## Next Steps

-> Implement in SKILL.md
