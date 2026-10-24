# Design — compositor-neutral nyx island

## Goal

Keep the full nyx UI and behaviour intact while making the two places that talk
to the compositor work on Hyprland **and** niri. Everything else is a faithful
copy of the upstream `MascotsOverlay.qml`; no public property, signal or
function consumed by `shell/ui/Mascots.qml` may change.

## Compositor split

Detection is runtime, from the session environment:

```qml
readonly property string compositor: String(Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
readonly property string niriSocket: String(Quickshell.env("NIRI_SOCKET") || "")
readonly property bool isNiri: compositor.indexOf("niri") !== -1 || niriSocket !== ""
readonly property string cursorProvider: String(Quickshell.env("NYX_CURSOR_PROVIDER") || "")
```

`XDG_CURRENT_DESKTOP` contains `niri` under a niri session and `Hyprland`
under Hyprland; `NIRI_SOCKET` is set by niri even when the desktop name is
customised. Detection is session-wide, so these `readonly property`
declarations live on the root `Variants` object; the `Process` objects that
consume them are per screen, so each surface selects its own.

| Touch point    | Hyprland                                   | niri                                          |
| -------------- | ------------------------------------------ | --------------------------------------------- |
| Cursor         | `hyprctl cursorpos` loop (`cursorProc`)    | optional `NYX_CURSOR_PROVIDER` (`niriCursorProc`) |
| Window events  | `.socket2.sock` via `socat` (`eventsProc`) | `niri msg --json event-stream` (`niriEventsProc`) |

The unselected process is simply not run; QML `Process` objects with
`running: false` start no child and consume nothing.

## Exact patched regions

Relative to upstream `equisdots/nyx/front/MascotsOverlay.qml` at `abfd0f9`:

1. **Header comment.** The title names both compositors and a short
   "Compositor neutrality" paragraph points at the split; the cursor and
   window-event bullets describe both.

2. **Compositor awareness properties** (on the root `Variants`, after
   `speciesOptions`). Adds the four declarations above.

3. **Cursor region.**
   - Section comment updated to cover both compositors.
   - `cursorProc.running: root.enabled` becomes
     `root.enabled && !root.isNiri`.
   - Added `niriCursorProc` with
     `running: root.enabled && root.isNiri && root.cursorProvider !== ""`,
     command `["bash", "-c", root.cursorProvider]`, feeding
     `overlay.updateCursor` with the same `"x,y"` line contract.
   - Without a provider `cursorHere` stays false, so the mascots idle with
     centred pupils. `updateCursor` is unchanged.

4. **Window-event region.**
   - Section comment updated to cover both compositors.
   - `eventsProc.running: root.enabled` becomes
     `root.enabled && !root.isNiri`.
   - Added `niriEventsProc`, command
     `["bash", "-c", "niri msg --json event-stream 2>/dev/null"]`,
     `running: root.enabled && root.isNiri`, `SplitParser` -> `niriHandleEvent`.
   - Added `niriHandleEvent(line)`: substring match on the JSON variant name —
     `WindowOpenedOrChanged` / `WindowClosed` call `overlay.react()`,
     `WindowFocusChanged` calls `overlay.pickMood(...)`, then `idleTimer` is
     restarted. `handleEvent` (Hyprland) is kept verbatim.

The upstream layer-surface fix (`dockHeld`, `panelLayoutSpan`, fixed panel
height, reveal-driven joined notch, clipped dock/popover reveal, gated
animation timer, arrow-function click handler) is carried verbatim; it is not
a niri delta. Nothing else differs: use `diff` against the upstream file to
confirm the patch stays confined to these regions.

## Why the niri cursor degrades

niri deliberately has no IPC for the global pointer position. The only sources
of absolute pointer location are privileged (reading `/dev/input` directly).
A shell cannot assume that access, so the default must be "no cursor": the
overlay leaves `cursorHere` false and the mascots idle, which is a valid,
quiet state. The optional provider hook exists for users who *do* have raw
input access and accept the experimental transform from device units to screen
coordinates.

The provider is polled only when `isNiri` is true and `NYX_CURSOR_PROVIDER` is
non-empty, so Hyprland users and niri users without the hook pay no cost.

## Application and rollback

This repository is an overlay, not a shell: the niri meta merges it by
copying every file under `overlay/ui/plugins/nyx/**` onto the same relative path under
the shared shell tree.

```
overlay/ui/plugins/nyx/**  ->  ~/.config/hypr/scripts/quickshell/ui/plugins/nyx/**
```

`MascotsOverlay.qml` replaces the deployed upstream file (faithful copy plus
the patched regions above); `nyx-cursor-provider.sh` is added. Nothing else is
touched: the mascots, `MascotDock`, the `host` adapter, `nyx.json` and the
`ui/PluginHosts.qml` wrapper are shared inputs and must not be edited here.
`MascotDock.qml` gained `unfoldUp` and reveal clipping, and
`host/Mascots.qml` debounces the wallpaper preview, in `abfd0f9`; both changes
are compositor-neutral and are expected from the base deploy, so the overlay
does not duplicate them.

Rollback restores the pristine `MascotsOverlay.qml` (re-run the dots installer
for the `nyx` module, or copy the file back from the shared repository), then
optionally removes `nyx-cursor-provider.sh` and unsets `NYX_CURSOR_PROVIDER`.
The exact commands and the backup step are in
[docs/overlay.md](docs/overlay.md).

## Hard UI rule

When touching any widget, panel or overlay in this tree: **do not introduce
blank or empty spaces in a widget/panel.** Layouts must stay content-fitting.
Rows, columns and grids size to their contents and collapse cleanly; never
reserve empty room for absent sections. The island and dock rely on this so
they never draw dead area (which would also break the input mask and
click-through behaviour).

## Project conventions

- All code, comments and documentation are written in **English**.
- **No emojis** anywhere (code, comments, commits, docs). Nerd Font glyphs are
  existing UI content and are not emojis.
- The shared nyx files are read-only inputs: never edit them here; patch via
  this overlay instead.
- The overlay is a faithful copy plus the smallest possible diff. Keep it that
  way.
