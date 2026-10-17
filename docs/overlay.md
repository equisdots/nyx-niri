# Overlay map

This repository is merged by the niri meta into the shared shell tree at:

```
TARGET_ROOT=~/.config/hypr/scripts/quickshell/
```

The overlay mirrors that layout, so every file under `overlay/` maps onto the
same relative path under `TARGET_ROOT`:

```
overlay/ui/plugins/nyx/**  ->  ~/.config/hypr/scripts/quickshell/ui/plugins/nyx/**
```

## File-by-file merge map

| Source (this repo)                                        | Target                                              | Action   |
| --------------------------------------------------------- | --------------------------------------------------- | -------- |
| `overlay/ui/plugins/nyx/front/MascotsOverlay.qml`                 | `$TARGET_ROOT/ui/plugins/nyx/front/MascotsOverlay.qml`      | replace  |
| `overlay/ui/plugins/nyx/scripts/nyx-cursor-provider.sh`           | `$TARGET_ROOT/ui/plugins/nyx/scripts/nyx-cursor-provider.sh`| add      |

- **replace** — the target already exists (deployed from the shared `nyx`
  repository). The overlay version is a faithful copy with only the compositor
  touch points patched; see [../DESIGN.md](../DESIGN.md) for the exact regions.
- **add** — the target is new. The provider script ships disabled; the overlay
  only runs it when `NYX_CURSOR_PROVIDER` is set.

Create the scripts directory if the deploy step does not already:

```sh
mkdir -p "$TARGET_ROOT/ui/plugins/nyx/scripts"
```

## What is unchanged

These shared files are **not** in the overlay and must never be edited here:

- `ui/plugins/nyx/front/MascotDock.qml`
- `ui/plugins/nyx/mascots/` (all species, `Mascot.qml`, `MascotFaceEyes.qml`,
  `MascotMetrics.js`)
- `ui/plugins/nyx/nyx.json`
- `ui/PluginHosts.qml` (the generic mount for the plugin `host` adapter)

The public API of `MascotsOverlay` (`enabled`, `species`, `count`, `size`,
`uiScale`, `position`, `appearance`, `dock*`, `palette`, `cursorX/cursorY/
cursorHere`, `widgets`, `widgetList`, `widgetLauncher`, signals, and so on) is
byte-for-byte compatible with the wrapper, so no shell change is required.

## Rollback

Reverting is a two-step restore, because the merge overwrites a shared file and
adds a new one:

1. **Restore the shared `MascotsOverlay.qml`** from the pristine `nyx` source,
   e.g. re-run the dots installer for the nyx module, or copy it back from the
   shared repository:

   ```sh
   cp /path/to/equisdots/nyx/front/MascotsOverlay.qml \
      "$TARGET_ROOT/ui/plugins/nyx/front/MascotsOverlay.qml"
   ```

2. **Remove the added provider script** (optional, harmless if left):

   ```sh
   rm -f "$TARGET_ROOT/ui/plugins/nyx/scripts/nyx-cursor-provider.sh"
   ```

Then unset `NYX_CURSOR_PROVIDER` from the niri session environment and restart
Quickshell (`qs`). The overlay leaves no other state behind.

To keep a safety copy during a merge, back the target up first:

```sh
cp "$TARGET_ROOT/ui/plugins/nyx/front/MascotsOverlay.qml" \
   "$TARGET_ROOT/ui/plugins/nyx/front/MascotsOverlay.qml.bak"
```
