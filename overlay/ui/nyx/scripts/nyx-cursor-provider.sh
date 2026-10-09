#!/usr/bin/env bash
#
# nyx-cursor-provider.sh — OPTIONAL, EXPERIMENTAL absolute pointer provider.
#
# niri exposes no IPC for the global pointer position, so MascotsOverlay cannot
# use the `hyprctl cursorpos` loop it uses on Hyprland. This script is an
# optional external source: point the shell at it through the environment
# variable NYX_CURSOR_PROVIDER and the overlay will poll its stdout.
#
# Contract
#   - Prints one "x,y" line per update to stdout (decimal, comma separated).
#   - Diagnostics go to stderr only; stdout is reserved for the contract.
#   - Exits cleanly (status 0, no stdout) when the source is unavailable or
#     when raw input access is not granted. It is never fatal to the shell.
#
# Why it is experimental
#   - It needs privileged raw input access (root, or membership in the "input"
#     group) to read /dev/input via `libinput debug-events`.
#   - libinput reports POINTER_MOTION_ABSOLUTE coordinates in the device's own
#     coordinate space (often millimetres for absolute devices), NOT in screen
#     pixels. A downstream transform may be required before the values map to
#     the compositor's output geometry.
#   - Normal mice only emit relative deltas, so absolute motion is frequently
#     absent and the mascots simply stay idle. That is the expected fallback.
#
# Usage (opt-in, per session):
#   export NYX_CURSOR_PROVIDER="$HOME/.config/hypr/scripts/quickshell/ui/nyx/scripts/nyx-cursor-provider.sh"
#
# This script ships DISABLED by default: the overlay only starts it when
# NYX_CURSOR_PROVIDER is set to a non-empty command.
#
set -euo pipefail

note() { printf 'nyx-cursor-provider: %s\n' "$*" >&2; }

if ! command -v libinput >/dev/null 2>&1; then
    note "libinput not found; absolute pointer source unavailable (idle pupils)."
    exit 0
fi

# Reading /dev/input requires root or membership in the "input" group. Without
# it `libinput debug-events` only fails, so bail out early and cleanly.
if [ "$(id -u)" -ne 0 ] && ! id -nG 2>/dev/null | tr ' ' '\n' | grep -qx 'input'; then
    note "no raw input permission (need root or the 'input' group); nothing to stream."
    exit 0
fi

note "streaming best-effort absolute pointer events (device units, experimental)."

# Keep the stream alive across device hot-plug; restart after a short pause.
# Only POINTER_MOTION_ABSOLUTE carries an absolute position. The numeric pair
# after the event type is "x/y"; capture both sides.
while true; do
    libinput debug-events 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *POINTER_MOTION_ABSOLUTE*)
                if [[ $line =~ ([0-9]+(\.[0-9]+)?)/[[:space:]]*([0-9]+(\.[0-9]+)?) ]]; then
                    printf '%s,%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
                fi
                ;;
        esac
    done || true
    sleep 1
done
