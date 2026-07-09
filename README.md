# fleet-template

A **control plane** for your work across GitHub: one repo that holds the *map* of
your projects and the *orchestration* of AI agent sessions run against them,
using [thurbox](https://github.com/Thurbeen/thurbox). The defining constraint is
that the control plane holds the plan and the log, and never holds the workers'
branches — real work happens in thurbox worker sessions, each in its own git
worktree in a real repo. What accumulates here is playbooks (reusable recipes)
and run logs (what actually happened).

Click **Use this template** to make your own. It holds context and intent, not
code.

## Quickstart

From a fresh clone:

1. **Use this template**, then clone your new repo.
2. Edit `registry/owners.txt` — your GitHub username, plus any orgs you belong
   to, one per line. The sync refuses to run while the file has no active
   entries, rather than emit an empty map.
3. `./scripts/sync-registry.sh` — writes `registry/repos.generated.yaml` from
   your live `gh` session. Commit the result.
4. `./scripts/install-extension.sh` — renders `extension.toml` and installs the
   thurbox extension.
5. Open the `fleet` session in thurbox and give it a goal.

Requires `gh` (authenticated), `jq`, and `thurbox-cli`.

## Layout

```
registry/
  owners.txt               The GitHub owners the map covers, one per line.
  repos.generated.yaml     Auto-synced index of every repo (owners → repos).
                           GENERATED — do not hand-edit.
  context/
    _TEMPLATE.md           Copy this to add a project.
    <repo>.md              Curated notes: purpose, relations, active goals.

orchestration/
  playbooks/
    _TEMPLATE.md           Copy this to add a reusable orchestration recipe.
    <name>.md              A repeatable way to run thurbox for a class of work.
  runs/
    _TEMPLATE.md           Copy this per orchestration run.
    <date>-<slug>.md       Log of one run: goal, sessions, outcomes.

scripts/
  install-extension.sh     Renders extension.toml, then installs it.
  sync-registry.sh         Regenerates repos.generated.yaml from the GitHub API.
  sync-checkout.sh         Fast-forwards main when that is unambiguously safe.
  trust-thurbox-dir.sh     Seeds Claude Code workspace trust for a worktree.

.github/workflows/
  ci.yml                   PR checks feeding a single "All Checks" gate.
```

## The map

`registry/repos.generated.yaml` is a machine view — regenerated from GitHub, so
it never drifts. Everything a human (or an agent) actually needs to *understand*
a project lives in `registry/context/<repo>.md`, which the sync never touches.
That is where judgement goes: what a project is for, how it relates to the
others, what is parked and why.

The sync runs **locally**. It enumerates every repo you can reach using your own
`gh` session and keeps the ones owned by an owner in `registry/owners.txt`, so
there is no cloud PAT and no CI secret to manage. Refresh the map whenever you
like, then push:

```bash
./scripts/sync-registry.sh
git commit -am "chore(registry): sync" && git push
```

## Orchestration

The control plane drives [thurbox](https://github.com/Thurbeen/thurbox)
**directly** — it does not depend on any external orchestration skill.

### The run loop

1. **Clarify the goal.** Vague goals produce vague workers.
2. **Pick or write a playbook** in `orchestration/playbooks/`.
3. **Open a run log** from `orchestration/runs/_TEMPLATE.md`, named
   `<YYYY-MM-DD>-<slug>.md`.
4. **One worker session per unit of work.** Each targets a real repo and its own
   git worktree. Workers share no context with the lead and none with each
   other, so every prompt states the goal, the constraints, and what "done"
   looks like, from scratch.
5. **Record outcomes as they happen** — session name, repo, intent, PR. The run
   log is the source of truth for what happened, not your memory of it.
6. **Review the PRs**, then delete each session as it closes out.

Fast-forward a target repo's base branch *before* spawning a worker against it.
A stale local `main` is inherited by the new worktree: the worker does correct
work and its PR arrives conflicting.

### The mailbox convention

A worker finishes by mailing its result to the lead:

```bash
thurbox-cli message send --to <lead> --kind result --body '<PR url or NOT_APPLICABLE>'
```

and the lead drains the inbox exactly-once:

```bash
thurbox-cli message inbox --for <lead> --claim --json
```

This beats polling `gh pr list` on three counts. It is **exact** — the worker
names its own artifact instead of you inferring it from a PR list that may
contain someone else's. It is **immediate** — `message send` wakes the
recipient, so the lead never polls at all. And it can report **"not
applicable"**, which a PR poll can never distinguish from "still working": the
absence of a PR is not a signal. Because the payload travels through thurbox's
durable database rather than a tmux pane, it also survives scrollback, TUI
chrome, and line-wrapping — all of which make pane-scraping fragile.

See [`orchestration/playbooks/_TEMPLATE.md`](orchestration/playbooks/_TEMPLATE.md)
for the anatomy of a playbook, [`CLAUDE.md`](CLAUDE.md) for how an agent should
operate inside this repo, and
[`.claude/skills/thurbox-session/SKILL.md`](.claude/skills/thurbox-session/SKILL.md)
for the detailed driving surface: spawning, prompting, completion detection,
cleanup.

## Thurbox extension

The repo ships [`extension.toml.in`](extension.toml.in), so thurbox can keep the
control plane running as a first-class session:

```bash
./scripts/install-extension.sh
```

That registers exactly two things:

- **A `fleet` agent** in `agents.toml` — `claude` pinned to Opus, resuming and
  forking by thurbox's session id like the stock `claude` agent.
- **A long-lived `fleet` session**, whose standing context is
  [`FLEET.md`](FLEET.md) (symlinked to `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`
  in the extension home). thurbox **self-heals** it: delete the session and it
  comes back. Because it is a real session, workers can mail their results to it
  with `thurbox-cli message send --to fleet`.

Payload files land in `~/.config/thurbox/extensions/fleet/`; the registry,
playbooks, and run logs stay in your checkout, where they are versioned.

### Why the manifest is a `.in` file

`[[sessions]] repo_path` must be an **absolute path** to your clone. thurbox
does not expand `~` there: `ExtensionDef::resolved_for_home()` substitutes the
`{home}` token but never calls `expand_tilde`, so a leading tilde is taken
literally and the session lands in a directory named `~`. And `{home}` itself
resolves to the *extension home*, not your checkout — while the session must
open the checkout, because it needs `registry/` and `orchestration/` in hand.

A template cannot hardcode a path that exists on one machine. So the manifest
ships as `extension.toml.in` with a `__REPO_PATH__` placeholder, and
`scripts/install-extension.sh` renders it to a gitignored `extension.toml`
carrying your clone's real path. Re-run the installer after moving the clone.

There are deliberately **no automations**. The one scheduled candidate — the
registry sync — commits and pushes to `main`, so it stays a manual
`./scripts/sync-registry.sh` run by a human who reads the diff.

```bash
thurbox-cli extension status fleet     # per-resource health
thurbox-cli extension deactivate fleet # the real off-switch
thurbox-cli extension uninstall fleet  # reverse the install
```

## License

MIT — see [LICENSE](LICENSE).
