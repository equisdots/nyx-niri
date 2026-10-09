# equisdots niri — nyx-niri

Compositor-neutral overlay for the shared `nyx` mascot island. It lets the
same island run on both Hyprland and [niri](https://github.com/YaLTeR/niri)
while keeping the rest of the shell untouched. It is consumed by the niri meta
package, which merges `overlay/` into the shared shell tree.

## Overlay model

The shared `nyx` module lives in its own repository and is deployed by the
dots installer under `~/.config/hypr/scripts/quickshell/ui/nyx/`. This
repository is an **overlay**: it contains only the files that differ from that
shared tree, mirroring the deployed layout under `overlay/`. The niri meta
copies `overlay/` over the shared tree, replacing the patched files and adding
the new ones. Nothing else in the shared shell is touched.

```
overlay/ui/nyx/front/MascotsOverlay.qml              -> quickshell/ui/nyx/front/MascotsOverlay.qml
overlay/ui/nyx/scripts/nyx-cursor-provider.sh        -> quickshell/ui/nyx/scripts/nyx-cursor-provider.sh
```

`MascotsOverlay.qml` is a faithful copy of the upstream file except for the
two compositor touch points described below. The provider script is new.

## Niri cursor limitation and fallback

Hyprland tracks the pointer with a small `hyprctl cursorpos` polling loop. niri
has **no IPC for the global pointer position**, so that loop is impossible
there. Under niri the overlay therefore degrades gracefully:

- The Hyprland cursor loop and the Hyprland `socket2` event stream are stopped.
- Window events come from `niri msg --json event-stream` instead.
- With no cursor source, `cursorHere` stays `false` and the mascots idle
  (pupils stay centred). This is the default and it is fully supported.

## Provider hook

Global cursor tracking under niri needs privileged raw input access, so it is
opt-in and experimental. Set `NYX_CURSOR_PROVIDER` to a command whose stdout is
a stream of `x,y` lines; the overlay polls it only on niri:

```sh
export NYX_CURSOR_PROVIDER="$HOME/.config/hypr/scripts/quickshell/ui/nyx/scripts/nyx-cursor-provider.sh"
```

The bundled `nyx-cursor-provider.sh` is a best-effort example built on
`libinput debug-events`; it needs root or the `input` group and ships disabled.
It prints nothing and exits cleanly when unsupported. See
[DESIGN.md](DESIGN.md) for the rationale and [docs/overlay.md](docs/overlay.md)
for the merge map and rollback.

## Merge target

The niri meta merges this overlay into the shared shell tree at:

```
~/.config/hypr/scripts/quickshell/
```
