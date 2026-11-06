# Publishing on the Steam Workshop

The Workshop accepts Lua and game assets only, no `.dll`. The Workshop item is the gamemode; the radio module
is downloaded separately from your GitHub release.

## Upload (Windows, the tools come with Garry's Mod)

The Workshop item is exactly the repository's `addon/mayhem_fpv` folder, and the preview picture is
`branding/workshop_icon.jpg`. Open a command prompt (Win+R, `cmd`) and run, with your own paths:

```
cd "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin"
gmad.exe create -folder "C:\Users\you\Documents\GitHub\mayhem-fpv\addon\mayhem_fpv" -out "C:\temp\mayhem_fpv.gma"
gmpublish.exe create -addon "C:\temp\mayhem_fpv.gma" -icon "C:\Users\you\Documents\GitHub\mayhem-fpv\branding\workshop_icon.jpg"
```

Create the `C:\temp` folder first if it doesn't exist. `python tools/package.py` also checks every file
against the Workshop whitelist and builds the same folder in `dist/workshop/`.

`gmpublish create` prints the Workshop ID. Updates:

```
gmpublish.exe update -addon "C:\temp\mayhem_fpv.gma" -id <ID> -changes "v0.7.1: ..."
```

Steam must be running. A new item is hidden until you accept the Workshop terms and set its visibility on the item page.

## Text for the Workshop page

> **RC radio?** Download `gmcl_fpvjoy_win64.dll` from the GitHub releases page and put it in
> `garrysmod\lua\bin\`, then restart Garry's Mod. Gamepads and the keyboard work without it.
> Needs the **x86-64 beta** branch of Garry's Mod.

## Testing the Workshop build locally

Copy `addon/mayhem_fpv` to `garrysmod/addons/mayhem_fpv` and restart Garry's Mod (the gamemode list is
read at startup). Once you subscribe to the real Workshop item, delete the local copy so only one is loaded.
