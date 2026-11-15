# Releasing MightiePack

Order matters. Two steps belong to the owner alone; one must happen *before* his word, not after.

## The sequence

1. **Merge what the release carries** — through review, CI green at the exact head, merged by review.
2. **CUT THE CHANGELOG BEFORE THE TAG WORD — NEVER AFTER.** Add the version's section to
   `CHANGELOG.md` on `main` as it will ship, and let `[Unreleased]` accumulate the *next* version.
3. **The owner names the head for his deploy test.** Sync that exact commit to his client with a
   receipt and a full backup; parity must pass; verify the installed bytes yourself.
   Deploy **only** a head he has named — "ready for retest" is a report, not a deploy trigger.
4. **The owner tests it in game.**
5. **The owner gives the tag word, naming the commit.** Tag **exactly that commit** — a build that
   differs from the one he tested is not the build he tested — push the tag, and confirm the
   Release workflow uploaded.
6. Record the receipt, the tag and the upload in the release's board notes.

## Why step 2 comes before step 5, and cannot be reordered

`.pkgmeta` declares `manual-changelog: CHANGELOG.md`, and the packager reads that file **from the
tagged commit**. A changelog commit made after the tag cannot change what that release published; it
only documents the release afterwards in the repository, which is worth doing but is not a release
record.

This is not hypothetical: **v0.3.8-beta was tagged before its entry existed**, so its CurseForge page
shows 0.3.7's notes. The repository was corrected afterwards. The fix is the ordering above — the
changelog is cut while the release is still un-tagged, so the file the packager reads already
describes the release it is packaging.

## What the tag workflow does

A pushed tag matching `v[0-9]*` triggers `.github/workflows/release.yml`, which **refuses any tag
whose commit is not an ancestor of `origin/main`**, then runs BigWigsMods/packager with the
`CF_API_KEY` repo secret and uploads to CurseForge project **1788533**. Confirm the run's own log
line (`Uploading … to https://wow.curseforge.com/projects/1788533`) rather than inferring success
from a green badge.
