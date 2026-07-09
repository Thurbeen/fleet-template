# Run: <YYYY-MM-DD> — <slug>

> Copy to `orchestration/runs/<YYYY-MM-DD>-<slug>.md`. This log is the source of
> truth for what happened.

- **Goal.** What this run is meant to achieve.
- **Playbook.** `../playbooks/<name>.md` (or "ad hoc").
- **Started.** <date/time> · **Status.** planning | running | done | abandoned

## Sessions

| Session name | Repo | Intent | Status | Artifact / PR |
|---|---|---|---|---|
| `fleet-...` | `owner/repo` | one line | running / done | link |

## Timeline

- <time> — launched `fleet-...` against `owner/repo`.
- <time> — drained the inbox; `fleet-...` reported …

## Outcome

What shipped, what's pending, what to follow up on. Update the relevant
`registry/context/<repo>.md` if this run changed a project's goals or relations.
