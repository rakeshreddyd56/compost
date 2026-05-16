# PR review process — Codex 5.5 reviews Claude Code's work

> Workflow rule (in effect 2026-05-16): everything Claude Code writes lands on a feature branch and goes through PR review by Codex 5.5 before merging to `master`.

## Why
- Two-agent setup with one human (rakesh). Catches Claude's hallucinations + style drift before they hit main.
- Forces small, atomic units of work (one PR per logical change).
- Creates a reviewable diff trail judges can scroll through (proof of agent collaboration).

## Branch naming
- `claude/<sprint>-<short-description>` — e.g. `claude/s1-graceful-env-guard`, `claude/s2-gardener-scoring`

## Per-change workflow

### 1. Claude Code creates the branch
```bash
cd ~/compost
git checkout master && git pull
git checkout -b claude/<sprint>-<description>
# ... make changes ...
git add -A && git commit -m "[<scope>] <imperative>: <what>"
git push -u origin claude/<sprint>-<description>
```

### 2. Open PR with embedded Codex review prompt
```bash
gh pr create --title "..." --body "..."
```
The PR body **must** include a fenced `Codex review` section with the exact prompt to paste into Codex 5.5.

### 3. Rakesh runs Codex review locally
```bash
# In a Codex 5.5 session
gh pr view <num>           # see the prompt embedded in body
gh pr checkout <num>       # pull the branch locally
git diff master...HEAD     # see what changed
# Then paste the review prompt from the PR body into Codex
```

Codex outputs **APPROVE** or **REQUEST_CHANGES** with specific concerns.

### 4. Iterate or merge
- **APPROVE** → `gh pr merge <num> --squash --delete-branch`
- **REQUEST_CHANGES** → Claude makes the requested changes on the same branch, force-pushes, Codex re-reviews

## When to skip PR review
Only for trivial doc/typo changes — commit directly to master. Anything touching `workers/src/` or `app/Compost/*.swift` goes through PR.

## Conflict resolution
- Codex's review wins on **safety and correctness** (SDK usage, type safety, deletion guards)
- Claude's design intent wins on **product / UX shape** (the spec in `~/ObsidianVault/compost-hackathon/`)
- Rakesh breaks ties

## Commit message format
```
[<scope>] <imperative>: <one-line summary>

<optional body — what + why, not how>
```
- `<scope>` ∈ `workers | app | shared | docs`
- Imperative: "add", "fix", "guard", "wire", "rename"

## CI
None for v1. `npm run check` is the local gate before push. `gh pr create` doesn't block on anything.

## After merge
```bash
git checkout master && git pull
git branch -d claude/<sprint>-<description>     # already deleted on remote
```

---

## Live PRs
| # | Branch | Status |
|---|---|---|
| 1 | `claude/s1-graceful-env-guard` | open — awaiting Codex review |
