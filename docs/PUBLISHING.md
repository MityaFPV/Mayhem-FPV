# Publishing on GitHub, step by step

You only need a GitHub account and GitHub Desktop. No command line.

## 1. Put the code on GitHub (once)

1. Make an account at [github.com](https://github.com) if you don't have one.
2. Install [GitHub Desktop](https://desktop.github.com) and sign in with that account.
3. Unzip the repository folder `mayhem-fpv` somewhere permanent, for example `Documents\GitHub\mayhem-fpv`.
4. GitHub Desktop → **File → Add local repository** → choose the `mayhem-fpv` folder.
   It says the folder isn't a repository yet: click **create a repository**, keep the name `mayhem-fpv`,
   leave *Git ignore* and *License* on **None** (both files are already there), click **Create repository**.
5. Click **Publish repository**. Untick **Keep this code private** if everyone should see it. Click **Publish**.

The code is now at `https://github.com/<your-name>/mayhem-fpv`.

## 2. Make a release (every version)

A release is the download page players use.

1. On your repository page: **Releases** (right side) → **Draft a new release**.
2. **Choose a tag** → type `v0.7.0` → *Create new tag*.
3. Title: `Mayhem FPV v0.7.0 (open beta)`. Write a few lines about what's new.
4. Drag in the files from the release folder you got with this repository:
   - `mayhem-fpv-v0.7.0.zip` (full install: gamemode + DLL)
   - `gmcl_fpvjoy_win64.dll` (for Workshop players)
5. Tick **Set as a pre-release** while it's a beta. Click **Publish release**.

## 3. The game's download button

`FPV.MODULE_URL` in `addon/mayhem_fpv/gamemodes/mayhemfpv/gamemode/shared.lua` already points at
`https://github.com/MityaFPV/Mayhem-FPV/releases/latest`, so the Radio tab's **Get the radio module** button
always opens the newest release.

## 4. Updating later

1. Change the code. Raise the version in `shared.lua` (`FPV.Version = "0.7.1"`).
2. Build the release files (`python tools/package.py`, or ask whoever helps you build them).
3. GitHub Desktop: write a summary, **Commit to main**, **Push origin**.
4. Make a new release as in step 2 with the new tag and files.

## Good to know

- `dist/`, `module/build/` and `module/third_party/` are generated and stay out of the repository
  (`.gitignore`). The release files are uploaded to Releases, not committed.
- GitHub refuses single files over 100 MB. The biggest file here is about 12 MB.
- If someone reports a copyright problem with the music, delete the tracks from
  `addon/mayhem_fpv/sound/mayhem_music/`, commit, and make a new release.
