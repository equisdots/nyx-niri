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
readonly property bool isNiri: compositor.indexOf("niri") !== -1
readonly property string cursorProvider: String(Quickshell.env("NYX_CURSOR_PROVIDER") || "")
```

`XDG_CURRENT_DESKTOP` contains `niri` under a niri session and `Hyprland`
under Hyprland. These are declared on the per-screen `overlay` object so each
surface selects its own processes.

| Touch point    | Hyprland                                   | niri                                          |
| -------------- | ------------------------------------------ | --------------------------------------------- |
| Cursor         | `hyprctl cursorpos` loop (`cursorProc`)    | optional `NYX_CURSOR_PROVIDER` (`niriCursorProc`) |
| Window events  | `.socket2.sock` via `socat` (`eventsProc`) | `niri msg --json event-stream` (`niriEventsProc`) |

The unselected process is simply not run; QML `Process` objects with
`running: false` start no child and consume nothing.

## Exact patched regions

Relative to the original 734-line `equisdots/nyx/front/MascotsOverlay.qml`:

1. **Header comment** (original lines 9-61).
   - Line 10: "(Hyprland)" becomes "(Hyprland + niri)".
   - After line 14: added a "Compositor neutrality" paragraph describing the
     two touch points and the niri cursor limitation.
   - Lines 48-56 ("Behaviour" bullets): the cursor bullet and the window-event
     bullet now describe both compositors. No other comment changed.

2. **Compositor awareness properties** (inserted after original line 124,
   `screen: modelData`, before the `── derived config` section). Adds the
   three `readonly property` declarations above.

3. **Cursor region** (original lines 432-456).
   - Section comment updated to cover both compositors.
   - `cursorProc.running: root.enabled` becomes
     `root.enabled && !root.isNiri`.
   - Added `niriCursorProc` with
     `running: root.enabled && root.isNiri && root.cursorProvider !== ""`,
     command `["bash", "-c", root.cursorProvider]`, feeding
     `overlay.updateCursor` with the same `"x,y"` line contract.
   - `updateCursor` is unchanged.

4. **Window-event region** (original lines 458-475).
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

Nothing else was reformatted or moved. Use `diff` against the upstream file to
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
