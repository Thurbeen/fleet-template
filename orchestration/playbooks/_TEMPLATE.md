# Playbook: <name>

> A reusable recipe for running thurbox against a class of work.

**When to use.** The situation this playbook fits (e.g. "ship one scoped feature
to a single repo", "apply the same change across N repos").

**Targets.** Which repos / kinds of repos this applies to.

## Inputs

- `goal` — what the run should achieve.
- `<other>` — anything the operator must decide before launching.

## Sessions

How to decompose the goal into thurbox sessions. For each session, define:

- **name** — hyphenated, no spaces, ≤ 64 chars (e.g. `fleet-<slug>`).
- **repo / worktree** — the target repo and branch the worker operates on.
- **prompt** — self-contained; the worker never sees this conversation.
- **done when** — the acceptance signal (a PR, a passing test, a file).

## Run

1. Open a run log from `../runs/_TEMPLATE.md`.
2. Fast-forward each target repo's base branch, then `thurbox-cli session create`
   with `--parent "$THURBOX_SESSION"`.
3. `thurbox-cli session send <uuid>` the prompt, ending with the result-mail
   line so the worker reports back instead of you polling.
4. Drain `thurbox-cli message inbox --for "$THURBOX_SESSION" --claim --json`;
   record each outcome in the run log as it lands.
5. Review artifacts (PRs). `session delete <uuid> --force` per session as it
   closes out.

## Notes

Gotchas, ordering constraints, things that bit you last time.
