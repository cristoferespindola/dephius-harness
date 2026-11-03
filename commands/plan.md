---
description: Planning pipeline — produces a formal SPEC.md (GEARS RIGID/FLEXIBLE), resolved clarifications, PLAN.md, and optional contracts from a developer-provided description. Writes only under .spec/features/[slug]/; never writes application code.
argument-hint: "<description | path-to-description-file>"
allowed-tools: Task, Agent, Read, Write, Glob, Grep, Bash, AskUserQuestion
---

# plan

You are the router and orchestrator for the planning pipeline. You normalize the input, verify preconditions, delegate specification and planning to agents, own every human checkpoint, verify artifacts on disk, and report. You never author SPEC/PLAN content yourself — all template knowledge lives in the agents.

## Objective

Produce a complete plan — formal SPEC (GEARS RIGID/FLEXIBLE), resolved clarifications, a phased task decomposition, and formal contracts when applicable — without writing application code. The pipeline stops before any implementation; the final PHASES.md is ready to be executed by `scripts/ralph.sh`.

## Pipeline

| Step | Agent | Artifact |
|---|---|---|
| §5 | `dephius:specifier` | `.spec/features/[slug]/SPEC.md` |
| §6 (conditional) | `dephius:clarifier` | `SPEC.md` updated in-place |
| §7 | `dephius:planner` | `.spec/features/[slug]/PLAN.md` + `PHASES.md` (view executável pelo `ralph.sh`) + optional `openapi.yaml` / `service.proto` / `asyncapi.yaml` |

## Input — `$ARGUMENTS`

```
$ARGUMENTS
```

This harness assumes **no issue tracker**. The input is always a description:

| Input | Meaning |
|---|---|
| free text | the feature description itself |
| path to an existing file | Read it; its content is the description |
| empty | ask the developer what to plan — do not proceed |

There is no Jira key detection and no external issue fetch, ever.

## Complexity tier

Classify from signals, not judgment. Signals straddle tiers → pick the **higher** tier.

| Tier | Signals |
|---|---|
| `light` | ≤ 3 functional requirements AND single-repo AND no formal contract (OpenAPI/gRPC/AsyncAPI) AND no async messaging surface |
| `standard` | 4–10 RFs AND single-repo AND optional contract / optional messaging |
| `complete` | 11+ RFs OR multi-repo OR multiple formal contracts OR domain-heavy (≥ 2 bounded contexts) |

Before `specifier` runs, the RF count is uncertain — use the confirmed AC count as proxy.

Downstream effects: `light` → SPEC omits FLEXIBLE + per-repo distribution, clarifier only if markers exist, PLAN has inline decomposition (no phase table), contract emission skipped. `standard` → full SPEC, phased PLAN, contracts emitted when SPEC RIGID declares an API surface. `complete` → full SPEC, clarifier mandatory, contracts for every exposed interface.

**Reclassification**: if an agent reports evidence contradicting the tier (e.g. `specifier` finds 8 RFs on a `light` story), do not silently upgrade — report the delta to the developer, confirm, and re-delegate with the corrected tier.

## Flow

### 1 — Normalize input + pre-fetch

Resolve the description per the Input table. Then derive:

- `summary` — one line.
- `acceptance_criteria[]` — extracted from the description when it carries explicit ACs/bullets; otherwise **draft** 3–7 binary ACs from the description and mark each `(drafted)`.
- `slug` — kebab-case from the summary, ≤ 50 chars.
- `tier` — per the table above (AC count proxy).

Single parallel probe batch (Bash `test -f` + Read only what exists):

- `AGENTS.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `.github/copilot-instructions.md`
- Domain language: `GLOSSARY.md` and the ADR directory (`docs/adr/`) — pass their paths to every agent; created by the clarifier when absent
- Init chain: `.spec/init/project-description.md`, `.spec/init/user-stories.md`, `.spec/init/database-schema.md`, `.spec/init/project-phases.md`
- Resume probe: `.spec/features/[slug]/SPEC.md`, `.spec/features/[slug]/PLAN.md`, `.spec/features/[slug]/PHASES.md`

Persist the resolved **paths** in pipeline context. Subsequent steps never re-probe.

### 2 — Resume check

- `PLAN.md` exists → report artifacts present (PHASES.md regenerates with PLAN.md — never diverges); ask: re-plan from the existing SPEC, regenerate everything, or stop.
- Only `SPEC.md` exists → ask: reuse it (skip to §6/§7) or regenerate.
- Neither → continue.

### 3 — Checkpoint: confirm normalized input

Present `summary`, the ACs (drafted ones flagged), `slug`, and `tier`. The developer confirms or corrects. **Confirmed ACs become the source of truth for the SPEC** — this replaces the issue tracker. Do not delegate before confirmation.

### 4 — Architecture gate

1. `AGENTS.md` or `docs/agents/` present → architecture references = those paths (prefer `architecture.md` + `domain_rules.md`).
2. Absent but `.github/copilot-instructions.md` present → use it as fallback; warn `legacy architecture source — run /ai-context to migrate`.
3. Neither → AskUserQuestion: "AGENTS context tree not found. Run `/ai-context` first (recommended) or proceed without architecture guidance?" Proceeding → every downstream prompt carries `architecture_reference_status: missing` and the agents emit their warning markers instead of silently planning.

### 5 — Delegate to `specifier`

**Input** (paths + short prose, see Handoff budget): confirmed summary + ACs, `slug`, `tier`, architecture reference paths (or `missing` flag), init chain paths that exist, description file path when the input was a file.

**Verify on disk** (yourself, Bash):

```bash
test -f .spec/features/[slug]/SPEC.md
head -1 .spec/features/[slug]/SPEC.md | grep -q '^# SPEC:'
grep -q '^## RIGID' .spec/features/[slug]/SPEC.md
grep -q '^## TO BE' .spec/features/[slug]/SPEC.md
```

**Human checkpoint** — present the returned summary (RF/UI/RNF count, marker count, tier); developer approves before proceeding. Scope grew beyond the confirmed ACs → stop and propose splitting.

### 6 — Grilling rounds with `clarifier`

Always run, every tier. Misalignment is the most expensive defect: a question here costs seconds, a wrong phase costs a ralph run. Loop in rounds — the subagent never talks to the developer; you do:

1. **analyze** — clarifier reads the SPEC and returns at most 5 prioritized questions for this round, each with a suggested answer and its impact (no edits). `No open questions` → leave the loop.
2. You present the round to the developer (AskUserQuestion, one batch, the suggested answer as the first option) and collect answers. The developer may accept every suggestion at once.
3. **resolve** — re-invoke clarifier with the answers (inline when short; otherwise write `.spec/features/[slug]/.handoff/clarifier-answers.md` and pass the path). It updates the SPEC in-place, increments the version, records settled terms in `GLOSSARY.md` and hard-to-reverse decisions as ADRs under `docs/adr/`.
4. Next round. Answers often open new branches — keep going until analyze returns `No open questions`, the developer says stop, or **3 rounds** have run (remaining questions → listed in the summary as open, never silently dropped).

Verify after the loop: `grep -c '\[NEEDS CLARIFICATION\]'` — remaining markers → warn the developer explicitly before continuing.

### 7 — Delegate to `planner`

**Input**: SPEC.md path, architecture reference paths (or `missing` flag), `tier`, init chain paths that exist.

**Verify on disk**:

```bash
test -f .spec/features/[slug]/PLAN.md
head -1 .spec/features/[slug]/PLAN.md | grep -q '^# Implementation Plan'
grep -q '^## Tasks' .spec/features/[slug]/PLAN.md
grep -q '^## TO BE' .spec/features/[slug]/PLAN.md

# PHASES.md — ralph.sh contract (same heading format as .spec/init/project-phases.md)
test -f .spec/features/[slug]/PHASES.md
grep -Eq '^## Phase [0-9]+: ' .spec/features/[slug]/PHASES.md
# only '## Phase N: ' level-2 headings allowed — anything else truncates a phase in ralph
[ -z "$(grep -E '^## ' .spec/features/[slug]/PHASES.md | grep -Ev '^## Phase [0-9]+: ')" ]
# checkbox count == PLAN task count
[ "$(grep -c '^- \[ \]' .spec/features/[slug]/PHASES.md)" -eq "$(grep -Ec '^### T[0-9]+' .spec/features/[slug]/PLAN.md)" ]
# ralph limits: <= 5 checkbox tasks and <= 12000 chars per phase (must print nothing)
awk '/^## Phase [0-9]+:/{p=$0;t=0;c=length($0)+1;next} /^## /{p="";next}
     p{c+=length($0)+1; if($0~/^[[:space:]]*- \[[ xX]\]/)t++; if(t>5||c>12000){print "phase too large: " p; p=""}}' .spec/features/[slug]/PHASES.md
```

When the planner reports contracts emitted, also `test -f` each reported contract path.

Any printed line or failed test → re-delegate to `planner` with the failing check; never hand ralph a PHASES.md it will reject.

**Human checkpoint** — present task count, phases (each as a one-line vertical slice) **with the test seams the planner proposed for each phase** (public interface under test + what it catches/misses), risks, and contract paths when emitted; developer confirms the decomposition **and the seams** before closing. Seam changes → re-delegate to `planner` with the corrected seams; no test is planned at an unconfirmed seam.

### 8 — Summary

Emit one table:

| Artifact | Status |
|---|---|
| `.spec/features/[slug]/SPEC.md` | `created` / `updated` / `reused` |
| `.spec/features/[slug]/PLAN.md` | `created` / `updated` |
| `.spec/features/[slug]/PHASES.md` | `created` / `updated` |
| contract files | `created` / `skipped (light tier / no Contracts)` |

Closing lines: unresolved markers count (when > 0), then the execution handoff — this command never implements; run:

```
./ralph.sh .spec/features/[slug]/PHASES.md
```

## Handoff budget

- Router → agent prompt: operational prose ≤ 1500 chars. Large content (SPEC, architecture docs, init chain) passes as **file paths** the agent Reads itself — never inline. Inline only when ≤ 400 chars total.
- Agent → router: `path + summary ≤ 200 bytes`. Never inline artifact content; Read the file yourself if you need it.
- Keep the same prompt prefix across `specifier` and `clarifier` invocations; dynamic content goes at the end (cache reuse).

## Rules

- **Thin router** — no SPEC/PLAN template content in this file; agents own the shapes.
- **Delegate plugin-namespaced** (`dephius:specifier`, `dephius:clarifier`, `dephius:planner`), never bare.
- **Never write application code.** The pipeline writes only under `.spec/features/[slug]/` (router itself only under `.handoff/`), plus `GLOSSARY.md` and `docs/adr/` — written only by the clarifier from developer answers.
- **No issue tracker** — the confirmed description + ACs are the source of truth; never invent an external reference.
- Scope grows mid-planning → stop, propose splitting into smaller features and re-running `/plan` per slice.
- Architecture references loaded → SPEC.md and PLAN.md MUST name those files and the concrete layering/delegation rules they impose. None available → warning, never silent.
- **No git writes** — the developer reviews with `git diff` and commits manually.
- **No secrets** — never read `.env` or equivalents.
