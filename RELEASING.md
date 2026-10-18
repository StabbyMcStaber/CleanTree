# CleanTree GitHub Release Toolkit

This repository already has a tag-triggered GitHub Actions release workflow: `.github/workflows/release.yml`. The toolkit prepares a release locally, then triggers that existing workflow.

## One-time setup (Windows)

1. Install Git and [GitHub CLI](https://cli.github.com/).
2. Clone the repo: `git clone https://github.com/StabbyMcStaber/CleanTree.git`.
3. Run `gh auth login` once.
4. Use a clean, up-to-date `main` checkout.

## Publish a release

Open PowerShell from your CleanTree repository:

```powershell
git checkout main
git pull --ff-only
powershell -ExecutionPolicy Bypass -File .\scripts\release.ps1 -Version 1.2.1 -NotesFile .\my-notes.md
```

Without `-NotesFile`, a template release note is created. **Prefer a prepared notes file** before publishing so users see meaningful release notes. The script previews the notes and only proceeds if you type `RELEASE`. For unattended automation, `-Yes` skips confirmation.

The script checks authentication, clean worktree, synced main, and existing tags; then updates `CleanTree/CleanTree.toc`, saves `.github/release-notes/vVERSION.md`, commits and pushes main, and finally pushes an annotated `vVERSION` tag. The tag triggers GitHub Actions, which verifies the manifest version, builds `CleanTree-vVERSION.zip`, and creates the GitHub Release.

**Caution:** pushing the tag publishes to the public repository. If the version/notes commit is pushed but the tag push fails, inspect the state before retrying. Avoid manually deleting published tags.

Release status: https://github.com/StabbyMcStaber/CleanTree/actions/workflows/release.yml

All releases: https://github.com/StabbyMcStaber/CleanTree/releases
