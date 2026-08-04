---
name: mattstack:model-tiering
description: "Use when choosing which model to spawn a sub-agent, worker, or sub-claude on -- any decision point where a less capable model could handle the work. Covers spawn-time selection (shepherd picking worker models) and delegation-time selection (a worker dispatching sub-agents for subtasks)."
---

# Model Tiering

Use the least capable model that can succeed at each unit of work. An omitted
model flag inherits the parent's model -- usually the most expensive one --
which silently defeats tiering.

## The tier table

| Work shape | Model tier | Why |
|------------|-----------|-----|
| **Mechanical execution** -- fully specified, 1-3 files, existing pattern to follow, zero design decisions | Sonnet | Brief/plan contains everything. No triage or judgment needed. |
| **Design / triage** -- multiple valid approaches, vague criteria, cross-layer, product decisions, brainstorming | Opus | Agent must assess, brainstorm, make design calls. It delegates mechanical subtasks to cheaper sub-agents. |
| **Integration** -- merge branches, run verification, report | Sonnet | Mechanical by nature: merge, run tests, report. |
| **Review** -- disposable artifact or diff reviewer | Sonnet | Read-only, throwaway context. |

## Complexity signals

Use these to place a unit of work in the table above:

- **File count and isolation.** 1-3 files with a clear spec = mechanical. Multi-file with integration concerns = design tier.
- **Spec completeness.** Brief contains the exact code or precise instructions = mechanical. Brief describes intent and constraints = design tier.
- **Decision load.** Zero design decisions left = mechanical. Any product, architecture, or pattern decision = design tier.
- **Existing pattern.** Adding a field along an existing pattern, renaming, copy tweak = mechanical. New pattern, new component, new abstraction = design tier.

When in doubt, use the higher tier. A capable model on simple work wastes money; a simple model on complex work wastes everything.

## Tiering is recursive

A design-tier agent that runs the superpowers chain (brainstorming, spec, plan,
implement) should in turn dispatch its implementer sub-agents on cheaper models.
The plan's task descriptions carry the complexity signals: a task touching 1-2
files with complete code in the spec is mechanical; a task requiring broad
codebase understanding is design tier.

This recursion is how tiering saves the most: the expensive model does judgment
and orchestration; the cheap models do the volume work.

## Applying this skill

**As a shepherd** (spawning workers into herdr panes or worktrees): pick the
model from the tier table before spawning. Pass it explicitly via `-m`. If the
worker will triage its own work (e.g., reading a ticket and deciding the
approach), default to the design tier -- the worker needs the capability to
triage, then delegate downward.

**As a worker** (dispatching sub-agents for subtasks within a plan): pick the
model per task using the complexity signals. Superpowers' subagent-driven-development
skill covers the mechanics; this skill covers the decision.

**As a standalone agent** (deciding whether to do work inline or dispatch): if
the subtask is mechanical and isolated, dispatch it on a cheaper model. If it
requires your context or judgment, do it yourself.

## Domain overrides

Skills layered on top of this one may set a floor ("never use model X in this
repo") or a default ("ticket-driven work defaults to Opus because triage
happens inside the worker"). Those overrides are domain-specific; this skill
is the generic framework they override.
