# Lightroom Classic shortcut set

LightCraft ships a Lightroom-desktop keymap with some Lightroom Classic keys added. The
**Lightroom Classic** shortcut set gives the same commands Lightroom Classic's default keys,
where LightCraft has the command, in one click.

- **Help ▸ Keyboard Shortcuts** (`⌘/`): *Shortcut set: Lightroom (default) | Lightroom Classic*
  at the top of the editor.
- **Settings ▸ General ▸ Keyboard ▸ Shortcut set**: the same choice.
- **Control channel / CLI**: `app.keyProfile {"profile": "classic"}` or `{"profile": "lightroom"}`.
  Without `profile` it returns the active set (`{"profile": "lightroom"}`). An unknown name is
  refused and nothing changes.

```sh
lightcraft-cli run --connect --script - <<'EOF'
{"command": "app.keyProfile", "params": {"profile": "classic"}}
EOF
```

The choice is saved in `ui.json` as `settings.keyProfile` (`"lightroom"` or `"classic"`). A
`ui.json` written before this setting existed, or one with a value this build doesn't know,
reads as Lightroom.

**Your own shortcuts still win.** The set only changes the defaults *under* `settings.keymap`
(the keys you changed in the editor or with `app.setShortcut`). A key you gave a command keeps
it in either set. The set's key that would clash with yours goes quiet. A shortcut you removed
stays removed. ↺ in the editor (and `app.setShortcut {reset: true}`) restores the **active**
set's key. Reset All clears your changes and leaves the set as it is.

`⌘` is Ctrl on Windows and Linux; `⌥` is Alt.

## The mapping

Keys that change when you pick Lightroom Classic:

| Key | Lightroom Classic | LightCraft command | Key in the Lightroom set |
|---|---|---|---|
| `E` | Loupe | `view.detail` (Detail view) | `D` |
| `D` | Develop | `module.develop` (Detail view + Edit panel) | `⌘⌥2` |
| `C` | Compare | `view.compare` | `⇧C` |
| `R` | Crop overlay | `panel.crop` | `C` |
| `Q` | Spot Removal | `panel.remove` | `H` |
| `K` | Brush (Masking) | `tool.brush` | `B` |
| `M` | Linear Gradient | `tool.linear` | `L` |
| `⇧M` | Radial Gradient | `tool.radial` | `R` |
| `⇧W` | Masking panel | `panel.masking` | `M` |
| `⇧T` | Guided Upright | `tool.guidedUpright` | `⇧G` |
| `L` | Lights Out (cycle) | `view.lightsOut` | `⇧L` |
| `I` | Cycle info overlay | `view.infoOverlay` | `⌘I` |
| `H` | Hide / show pins (tool overlay) | `view.toolOverlay` (in the Masking panel `H` toggles the mask pins, as in both sets) | `⇧H` |
| `⌥O` | Cycle mask overlay mode | `view.maskOverlayMode` | none |
| `⌘U` | Auto | `develop.auto` | `⇧A` |
| `⌘⇧S` | Sync Settings | `develop.sync` (syncs without a dialog, like Classic's `⌘⌥S`) | none |
| `⌘⌥⇧M` | Match Total Exposures | `develop.matchExposure` | none |
| `⌘N` | New Snapshot (Develop) / New Collection (Library) | `version.create` while editing / `dialog.newAlbum` in the Library (see below) | `⌘⇧S` / `⌘N` |
| `⌘⇧N` | New Preset (Develop) / New Folder (Library) | `dialog.createPreset` while editing / `dialog.newFolder` in the Library | `⌘⇧P` / `⌘⇧N` |
| `⌘⇧E` | Export… | `dialog.export` | `⇧E` (secondary key, kept) |
| `⌘E` | Edit in Adobe Photoshop | `photo.editInExternal` (Edit in Other Editor: set Settings ▸ General ▸ Other editor to Photoshop) | `⌘⌥E` |
| `⌘⌥E` | Edit in Other Application | `photo.editInPhotoCraft` (Edit in PhotoCraft) | `⌘⇧E` |
| `⇧P` | Flag as Pick and advance | `photo.flag {pick, advance}` (secondary key, every view) | Presets panel (pick and advance only in the grids) |
| `Ctrl+Y` | Redo (Windows) | `edit.redo` (secondary key; `⌘⇧Z` stays) | none |
| `⌘⌥2` | Develop module | `module.develop` (secondary key) | `module.develop`'s own key |
| `⌘I` | Show / hide info overlay | `view.infoOverlay` (secondary key, cycles) | `view.infoOverlay`'s own key |

Keys the Lightroom set gives that the Classic set takes away, so nothing clashes:

| Command | Key in the Lightroom set | In the Classic set |
|---|---|---|
| `panel.edit` (Edit panel) | `E` | no key (`D` opens Develop with the Edit panel) |
| `panel.info` (Info panel) | `I` | no key |
| `panel.keywords` (Keywords panel) | `K` | no key (`⌘K` Add Keywords and `⌘⇧K` Edit Keywords stay) |
| `panel.presets` (Presets panel) | `⇧P` | no key |
| `app.exportPrevious` secondary key | `⌘E` | dropped (`⌘⌥⇧E`, Classic's key, stays) |
| `version.create` secondary key | `⇧M` | dropped (`⌘N` while editing) |
| `tool.quickMask` (Quick Mask) | `Q` | no key (`Q` is Spot Removal) |
| `tool.selectionCycle` (Quick / Object Selection) | `⇧W` | no key (`⇧W` is the Masking panel) |

The other Quick Retouch keys stay in both sets: `⇧B` steps Dodge / Burn / Sponge and `⇧Q` is
the Clone Stamp (Lightroom Classic's `⇧Q` luminance range mask has no LightCraft command).

Keys that are already Lightroom Classic's in both sets include:
`G` grid, `N` Survey, `⇧R` Reference view, `F` full-screen preview, `J` clipping, `V` black &
white, `W` white balance selector, `Z` / `Space` zoom, `Y` / `⌥Y` / `⇧Y` / `⌥⇧Y` / `\` before /
after, `O` / `⇧O` mask overlay, `P` / `X` / `U` / `` ` `` flags, `⌘↑` / `⌘↓` flag status, `0`–`5`
ratings, `6`–`9` labels, `⇧`+number and advance, `[` / `]` ratings in the grids, `B` Quick
Collection in the grids, `⌘[` / `⌘]` rotate, `⌘'` virtual copy, `⌘G` / `⌘⇧G` / `S` / `⇧S`
stacks, `⌘⇧C` copy settings, `⌘⌥V` paste from previous, `⌘⌥⇧A` auto sync, `⌘⇧R` reset,
`⌘⌥R` reset crop, `⌘⇧I` import, `⌘⌥⇧E` Export with Previous, `⌘K` / `⇧K` keywords, `⌘D`
(secondary key) select none, `⌘J` view options, `⌘L` filters, `⌘F` find, `⌘R` show in
Finder, `F2` rename, `F6` / `F7` / `F8` panels, `Ctrl+H` / `Ctrl+M` HDR and panorama merge,
and the module keys `⌘⌥1` Library, `⌘⌥6` Print.

## Keys that share by context

`⌘N` and `⌘⇧N` mean two things in Lightroom Classic, depending on the module. In LightCraft
the side is chosen by whether a photo is being edited: an edit tool's panel (Edit, Crop,
Masking, Remove, Red Eye, Profiles) open beside the photo means "Develop".

| Key | Editing a photo | Anywhere else (the grids, the Loupe with no edit panel) |
|---|---|---|
| `⌘N` | Create Version (Classic's snapshot) | New Album… (Classic's collection) |
| `⌘⇧N` | Create Preset… | New Folder… |

The menu bar shows the key on the item it runs at that moment (on macOS the native menu runs
it). If you move either command of a pair to a key of its own, both keys work everywhere.

`B` stays the Quick Collection in the grids: Lightroom's brush key `B` adds to the Quick
Collection there, and under Lightroom Classic the brush is `K` and `B` adds to the Quick
Collection by itself. `K` in a grid never touches the album.

## Not mapped

LightCraft has no command (or no command without parameters) for these Lightroom Classic keys,
so neither set binds them:

- `Tab` / `⇧Tab` / `T` / `F5`: hide side panels / all panels / toolbar / top panel.
- `⌘⌥3`–`⌘⌥5`, `⌘⌥7` (Map, Book, Slideshow, Web modules), `⌘⌥↑` previous module.
- `⌘0`–`⌘9` Develop panel tabs (LightCraft's sections are Lightroom's: `⌘1`–`⌘5`), and `⌘0`
  histogram (here `⌘⇧H`; `⌘0` is Zoom to Fit).
- `⌘⇧U` auto white balance, `⇧J` / `⇧Q` / `⇧Z` color / luminance / depth range masks, the
  targeted adjustment tool keys `⌘⌥⇧T/H/S/L/G`: these need parameters.
- `⇧A` (crop to the previous aspect), `/` brush A/B, `⌘⌫` delete rejected photos, `⌘B` show the
  Quick Collection, Caps Lock auto advance (bind `view.autoAdvance` yourself if you want a key).
- `O` People view: LightCraft's `O` is the mask overlay in both sets.
- `⌘⇧V` pastes through the Paste Selected Settings dialog in both sets (bind `develop.paste`
  to it for Classic's direct paste).

## For developers

- The set: `crates/ui-egui/src/keymap_profiles.rs` (`KeyProfile`, `CLASSIC_OVERRIDES`,
  `CLASSIC_ALIASES`, `CLASSIC_DROPPED_ALIASES`, `profile_default`, `aliases`). The setting is
  `AppSettings::key_profile`.
- `crate::shortcuts::binding(profile, keymap, id, default)` resolves a key: the user's entry,
  else the set's key (`profile_default`), which yields to a key the user gave another command.
  `shortcut_of`, `conflicts`, `assign` and `reset` take the set too.
- The `⌘N` / `⌘⇧N` pairs are in `shortcuts::CONTEXTUAL`; `shortcuts::contextual_yields` decides
  which side acts (the key handler and the menu bar both ask it).
- Tests: `crates/ui-egui/src/tests/classic_keymap.rs`. Among them,
  `the_classic_set_has_no_conflicting_bindings` checks every pair of commands and active
  secondary keys under both sets. Keys the Classic set adds are also checked the way Windows
  reads them (`⌘` = Ctrl). One clash on Windows is already in the shipped keymap and Classic
  leaves it as it is: `⌘⇧H` Histogram and `Ctrl+⇧H` HDR with Last Settings.

Adapted from upstream PR #2338 (storytold/lightcraft, MIT/Apache-2.0), ported to v0.20.0. The
module keys come from this patch set's module bar.
