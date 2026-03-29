---
date: 2026-03-28
topic: profile-folder-structure
---

# Profile Folder Structure

## What We're Building

Restructure profiles from one-big-file to one-folder-per-profile. Each profile becomes a folder containing a config file (`profile.md`) and separate prompt files for each agent role.

## Why This Approach

The single-file approach (`profiles/coding.md` at 595 lines) bundles config that humans tune (approach hints) with prompts that agents consume (implementer, reviewer, judge, synthesizer). These have different audiences and edit frequencies. The folder approach separates them while keeping everything co-located.

This also eliminates the `##` heading collision problem — profile sections previously shared the `##` level with internal prompt sub-headings, requiring whitelist-based extraction. With separate files, each prompt is its own file and needs no extraction logic.

## Key Decisions

- **One folder per profile**: `profiles/coding/`, `profiles/writing/`
- **`profile.md` is the config file**: Contains frontmatter (name, description, extends, isolation, pre_checks) and approach hints. ~40-50 lines. Fits on one screen.
- **Four prompt files per profile**: `implementer.md`, `reviewer.md`, `judge.md`, `synthesizer.md`. Each is self-contained — an agent receives this file's content and nothing else.
- **No subfolders within a profile**: The largest prompt (reviewer at ~240 lines) isn't big enough to warrant further decomposition.
- **Inheritance**: `profile.md` has `extends: coding`. Orchestrator loads base folder first, then overlays child's files. Missing files inherited from base.
- **SKILL.md simplification**: "Read `implementer.md` from the active profile's folder" replaces section extraction logic entirely.

## Structure

```
profiles/
├── coding/
│   ├── profile.md          # Frontmatter + approach hints (~40 lines)
│   ├── implementer.md      # Implementer prompt (~100 lines)
│   ├── reviewer.md         # Reviewer prompt (~240 lines)
│   ├── judge.md            # Judge prompt (~130 lines)
│   └── synthesizer.md      # Synthesizer prompt (~90 lines)
├── writing/
│   ├── profile.md          # Frontmatter + approach hints (~40 lines)
│   ├── implementer.md      # Writing-adapted implementer (~100 lines)
│   ├── reviewer.md         # Writing-adapted reviewer (~150 lines)
│   ├── judge.md            # Writing-adapted judge (~130 lines)
│   └── synthesizer.md      # Writing-adapted synthesizer (~90 lines)
```

## What Goes Where

### `profile.md` (config — human-readable)
- YAML frontmatter: name, description, extends, isolation, pre_checks
- Approach hints (a numbered list of style/strategy hints)
- Brief profile description (optional)

### Prompt files (agent-consumed)
- Full prompt text with `{{VARIABLE}}` placeholders
- Self-contained — no cross-references to other prompt files
- Same content as today's profile sections, just in separate files

## Impact on SKILL.md

- Remove the "Section Extraction from Profiles" subsection entirely
- Change all "Read the ## X Prompt section from the active profile" to "Read `x.md` from the active profile's folder"
- Profile discovery changes from "find `profiles/X.md`" to "find `profiles/X/profile.md`"
- Simpler parsing, no heading collision concerns

## Impact on Tests

- `test-skill-structure.sh`: Check for folder structure instead of sections in a single file
- `test-contracts.sh`: Read prompt files directly instead of extracting sections with sed
- Simpler, more reliable test extraction

## Open Questions

- None — this is a straightforward restructure of existing content.

## Next Steps

→ Implement as a follow-up task on the `feat/task-profiles` branch
