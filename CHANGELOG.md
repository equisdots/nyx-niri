# Changelog

All notable changes to `nyx-niri` are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Overlay target moved from `ui/nyx/` to `ui/plugins/nyx/`: Nyx is now a plugin
  (the shell mounts it through `ui/PluginHosts.qml` and the `host` adapter), so
  the niri overlay patches the plugin UI tree and is applied after the generic
  plugin deploy.
- `overlay/ui/plugins/nyx/front/MascotsOverlay.qml`: re-synced with the upstream `nyx`
  base — catalog-driven lineup (`mascotCatalog` / `speciesLineup`), per-species
  `options`, per-mascot popovers, and the declarative contract binding (fixes
  the `Item.palette` clash on Qt 6.6+). The niri split is unchanged: cursor via
  an optional `NYX_CURSOR_PROVIDER` loop and window events from
  `niri msg --json event-stream`.

## [0.1.0] - 2026-10-09

First release: compositor-neutral overlay for the shared `nyx` mascot island,
running on Hyprland and on niri 26.04 without changing the rest of the shell.

### Added

- `overlay/ui/plugins/nyx/front/MascotsOverlay.qml`: a faithful copy of the upstream
  island with a runtime compositor split selected from `XDG_CURRENT_DESKTOP`.
- `overlay/ui/plugins/nyx/scripts/nyx-cursor-provider.sh`: an optional, experimental
  absolute-pointer provider for niri, enabled with `NYX_CURSOR_PROVIDER`.
- niri window events via `niri msg --json event-stream`
  (`WindowOpenedOrChanged` / `WindowClosed` -> react, `WindowFocusChanged` ->
  mood).
- Documentation: `DESIGN.md` (design and patch regions) and `docs/overlay.md`
  (merge map, unchanged files, rollback).

### Notes

- niri has no IPC for the global pointer position. The mascots therefore idle
  with centred pupils unless `NYX_CURSOR_PROVIDER` streams `x,y` lines from a
  source with raw input access; hover reactions and window events still work.
- Hyprland behaviour is unchanged (`hyprctl cursorpos` loop plus the
  `.socket2` event stream).

[Unreleased]: https://github.com/equisdots/nyx-niri/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/equisdots/nyx-niri/releases/tag/v0.1.0
