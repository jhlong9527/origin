# Briar Warden Git backup guide

This project is backed up in the local Git repository at `D:\godot\warden\-666`.
The initial snapshot is commit `c7617ac` on branch `main`.

## Daily checkpoint

```powershell
Set-Location D:\godot\warden\-666
git status
git add .
git commit -m "feat: describe the change"
```

Use one commit per meaningful change (combat, boss, environment, art pass, etc.).

## Named milestones

```powershell
git tag -a v0.1-prototype -m "Playable prototype"
git tag -a v0.2-q-vfx -m "Q projectile and sword arc scale pass"
git push origin main --tags   # only after a remote is configured
```

## Compare and restore

```powershell
git log --oneline --decorate --all
git diff HEAD~1..HEAD
git restore path\to\file.gd       # discard local edits to one file
git switch -c rescue-before-experiment
```

## Remote backup

Create an empty private repository on GitHub/GitLab/your own Git server, then run:

```powershell
git remote add origin <PRIVATE_REPOSITORY_URL>
git push -u origin main
```

Do not commit passwords, API keys, or private credentials. For large binary assets, use Git LFS:

```powershell
git lfs install
git lfs track "*.blend" "*.glb" "*.psd" "*.fbx"
git add .gitattributes
git commit -m "chore: track source assets with Git LFS"
```

The repository intentionally ignores `.godot/`, `build/`, `captures/`, generated imports, logs, and Blender autosaves. Keep `.blend` and `.glb` source assets under version control; regenerate exports when needed.

