# Releasing

`scripts/release` cuts a new version of hyprecise. It dates the changelog, runs
the spec, tags the commit, pushes, and opens the GitHub release.

It never writes your release notes. You write those; the script does the
mechanics around them.

## The short version

```sh
# 1. Write the new section in CHANGELOG.md (see below)
# 2. See exactly what would happen — this changes nothing
scripts/release patch --dry-run

# 3. Do it
scripts/release patch
```

You will be shown the whole plan and asked to confirm before anything is
committed, pushed or published.

## Step 1 — write the changelog section

Open `CHANGELOG.md` and add a section at the top, just under the preamble and
above the previous release. Head it `## [Unreleased]` and the script will fill
in the number and today's date for you:

```markdown
## [Unreleased]

One or two sentences saying what this release is about.

### Fixed

- **A short bold claim.** Then the explanation, wrapped at 80 columns like the
  rest of the file.
```

Use `### Added`, `### Changed`, `### Fixed` and `### Removed` as needed — the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) headings the rest of
the file uses.

You can also write the version heading yourself — `## [1.0.2] — 2026-08-26` —
and commit it along with the code, which is how earlier releases were cut. The
script leaves a heading you have already dated exactly as written.

Either way, you do not need to add the `[1.0.2]: https://…/compare/…` link at
the bottom. The script adds it if it is missing.

## Step 2 — look before you leap

```sh
scripts/release patch --dry-run
```

This runs every check and prints what it would do, without touching anything:

```
hyprecise 1.0.2
  spec      119 passed, 0 failed
  changelog [Unreleased] becomes [1.0.2], dated 2026-08-26, compare link added
  commit    2f1c17b Move a boundary, not a column
  tag       v1.0.2, annotated "hyprecise 1.0.2"
  push      origin master, origin v1.0.2
  release   https://github.com/vitormil/hyprecise/releases/tag/v1.0.2, titled "1.0.2"
```

It also shows the diff it would make to `CHANGELOG.md` and the exact release
notes that will become the body of the GitHub release. Read those — they are
what the world sees.

## Step 3 — release

```sh
scripts/release patch
```

Same output, then `Release 1.0.2? [y/N]`. Only `y` or `yes` goes ahead, in either
case; anything else cancels and changes nothing. Add `--yes` to skip the prompt once you trust the plan.

## Choosing the number

| Bump | When |
|---|---|
| `patch` | A bug fix. Nothing about `setup()`, `keys`, `loop` or `min_width` changes. |
| `minor` | A new option or behaviour, with nothing that already worked breaking. |
| `major` | A breaking change to `setup()`, `keys`, `loop` or `min_width`. |

Those four are the supported surface, fixed at 1.0.0. Everything else the
module exposes — `M.run`, the callable module, the internals the spec reaches
for, and tuning knobs like `column_tolerance` — sits outside that promise, so
changing one of them does not force a major bump.

You can also name the version outright, which is what you want for a first
release or to skip a number deliberately:

```sh
scripts/release 1.2.3
```

## What it does, in order

1. Checks `gh` is installed and logged in, and that a Lua interpreter exists.
2. Checks you are on `master`, up to date with `origin`, and that nothing but
   `CHANGELOG.md` is uncommitted.
3. Works out the new number from the latest tag and refuses anything that does
   not come after it.
4. Checks the tag is free, both locally and on `origin`.
5. Runs `tests/hyprecise_spec.lua`. A failing spec stops the release here.
6. Dates the changelog heading and adds the compare link.
7. Shows you the plan and waits for your confirmation.
8. Commits `CHANGELOG.md` as `hyprecise 1.0.2` — but only if something actually
   changed. If the changelog already rode in on the feature commit, it simply
   tags `HEAD` and adds no commit of its own.
9. Tags `v1.0.2`, annotated, messaged `hyprecise 1.0.2`.
10. Pushes `master` and the tag.
11. Opens the GitHub release, titled `1.0.2`, with your changelog section as the
    body.

`hyprecise.lua` is never touched, so the running Hyprland config is unaffected
and no reload is needed.

## Options

| Flag | What it does |
|---|---|
| `--dry-run`, `-n` | Run every check and print the plan. Change nothing. |
| `--yes`, `-y` | Skip the confirmation prompt. |
| `--help`, `-h` | Print the usage summary. |

## When it refuses

Every one of these stops the release before anything has changed.

| Message | What to do |
|---|---|
| `CHANGELOG.md has no section for 1.0.2` | Write the section first — step 1. |
| `the 1.0.2 section of CHANGELOG.md is empty` | The heading is there but has no prose under it. |
| `the spec fails; nothing was released` | The failing output is printed above it. Fix the spec. |
| `uncommitted change in hyprecise.lua` | Commit or stash it. Only `CHANGELOG.md` may be dirty. |
| `on branch foo; releases are cut from master` | `git checkout master`. |
| `master is behind origin/master; pull first` | `git pull`. |
| `1.0.1 does not come after 1.0.1` | That version is already out. Bump further. |
| `tag v1.0.2 already exists locally` / `on origin` | Pick another number, or delete the stray tag. |
| `gh is not authenticated` | `gh auth login`. |

## If it stops halfway

The irreversible steps run only after you confirm, in this order: commit, tag,
push, release. If one fails, the ones before it have already happened.

```sh
# Tagged but not yet pushed — undo both the tag and the release commit
git tag -d v1.0.2
git reset --hard HEAD~1     # only if it made a commit; check git log first

# Pushed, but the GitHub release failed — finish it by hand
gh release create v1.0.2 --title 1.0.2 --notes-file notes.md
```

For that last one, paste the section out of `CHANGELOG.md` into `notes.md`
first — the script's own copy lives in a temp directory that is cleaned up when
it exits.
