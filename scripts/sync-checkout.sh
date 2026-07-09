#!/usr/bin/env bash
# Keep this checkout current with origin, safely.
#
# Wired to the SessionStart hook in .claude/settings.json, so every Claude Code
# session that opens the control plane starts from an up-to-date base. This
# exists because a stale local `main` is silently inherited by every new thurbox
# worktree: the worker branches off it, does correct work, and its PR arrives
# CONFLICTING. Fixing that after the fact costs a force-push.
#
# It only ever fast-forwards, and only when that is unambiguously safe:
#
#   dirty working tree        -> report, change nothing
#   not on the default branch -> report how far origin/<default> has moved
#   diverged from upstream    -> report, change nothing (never rebase/reset here)
#   strictly behind + clean   -> `git merge --ff-only`
#
# Prints a single JSON object on stdout. Claude Code reads `systemMessage` and
# shows it to the user; `suppressOutput` keeps the raw text out of the
# transcript. Always exits 0 — a sync problem must never block a session.

set -uo pipefail

emit() {
	# $1 = message. jq -n builds valid JSON regardless of quoting in $1.
	jq -cn --arg m "$1" '{systemMessage: $m, suppressOutput: true}'
	exit 0
}

command -v git >/dev/null || emit "control-plane sync: git not found; skipped."
command -v jq >/dev/null || exit 0 # cannot emit JSON without jq; stay silent

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo_root" || exit 0

# Network call: bounded, never hangs a session start.
if ! timeout 15 git fetch --quiet origin 2>/dev/null; then
	emit "control-plane sync: could not reach origin (offline?). Working from the local checkout."
fi

default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
[ -n "$default_branch" ] && [ "$default_branch" != "HEAD" ] || default_branch=main

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
remote_ref="origin/$default_branch"
git rev-parse --verify --quiet "$remote_ref" >/dev/null || exit 0

# Only *tracked* modifications block a fast-forward. Untracked files must not:
# a worker's BRIEF.md, or a stray note, would otherwise wedge every sync. If an
# untracked file genuinely collides with an incoming one, `merge --ff-only`
# refuses on its own and we report that below.
dirty=0
[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && dirty=1

# A worktree on a feature branch: report how far the base has moved, touch nothing.
if [ "$branch" != "$default_branch" ]; then
	behind_base="$(git rev-list --count "HEAD..$remote_ref" 2>/dev/null || echo 0)"
	if [ "$behind_base" -gt 0 ]; then
		emit "control-plane sync: on '$branch'; $remote_ref is $behind_base commit(s) ahead. Rebase before opening a PR, or it will conflict."
	fi
	exit 0
fi

behind="$(git rev-list --count "HEAD..$remote_ref" 2>/dev/null || echo 0)"
ahead="$(git rev-list --count "$remote_ref..HEAD" 2>/dev/null || echo 0)"

if [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then
	exit 0 # already current; say nothing
fi

if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
	emit "control-plane sync: '$branch' has diverged from $remote_ref ($ahead ahead, $behind behind). Left alone — reconcile by hand."
fi

if [ "$ahead" -gt 0 ]; then
	emit "control-plane sync: '$branch' is $ahead commit(s) ahead of $remote_ref and not pushed."
fi

# Strictly behind.
if [ "$dirty" -eq 1 ]; then
	emit "control-plane sync: '$branch' is $behind commit(s) behind $remote_ref, but the tree is dirty. Not fast-forwarding."
fi

if git merge --ff-only --quiet "$remote_ref" 2>/dev/null; then
	emit "control-plane sync: fast-forwarded '$branch' $behind commit(s) to $(git rev-parse --short HEAD)."
fi

emit "control-plane sync: '$branch' is $behind commit(s) behind $remote_ref and would not fast-forward. Left alone."
