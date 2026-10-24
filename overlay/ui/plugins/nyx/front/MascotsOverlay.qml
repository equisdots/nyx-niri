import QtQuick
import QtQuick.Shapes
import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../mascots"
import "../mascots/MascotMetrics.js" as Metrics

// ═══════════════════════════════════════════════════════════════════════════
// MascotsOverlay — standalone mascot island for Quickshell (Hyprland / niri).
//
// This file and its siblings (Mascot.qml, <Species>Mascot.qml, MascotFaceEyes,
// MascotDock) form a self-contained module that never imports the shell: the
// palette, the settings path and the widget hooks are injected.
//
// Compositor neutrality: the island runs on Hyprland and niri. Detection is
// runtime (XDG_CURRENT_DESKTOP or NIRI_SOCKET) and selects the cursor and
// window-event sources; see the compositor-awareness section below.
//
// Public API (per screen):
//   enabled            master switch (also read from the settings file)
//   species            "flame" | "cat" | "dog" | "eyes" | "mixed"
//   count              1..3 mascots in the island
//   size               0.6..1.6 mascot scale
//   uiScale            extra user scale (the shell's uiScale)
//   position           top-left | top-center | top-right | center-left |
//                      center | center-right | bottom-left | bottom-center |
//                      bottom-right (the dock unfolds toward the screen centre)
//   barPosition        "top" | "bottom" | other (edge margin for the island)
//   barThickness       bar thickness in px (edge margin)
//   appearance         "island" | "notch" (notch snaps to the top edge)
//   notchWidth         notch width in design px (clamped to fit the mascots)
//   notchHeight        notch height in design px (0 = automatic)
//   notchOffset        vertical offset in design px (may be negative)
//   notchReserve       reserve the top strip so windows clear the notch
//   dockSize           "compact" | "medium" | "large" | "wide" panel preset
//   dockWidth          explicit panel width in design px (0 = preset)
//   dockStyle          "floating" | "joined" (joined welds under the notch)
//   dockColumns/-Rows  widget grid columns / visible rows
//   dockShowHero/-Quick/-Search  panel section toggles
//   quickActions       [{ id, label, icon }] shortcut buttons
//   palette            { base, surface1, text, crust, red, yellow, green,
//                        blue, mauve, glassOn } — falls back to Catppuccin
//   settingsPath       optional settings.json to watch ("mascots", "uiScale",
//                        "bar.position", "bar.thickness" keys)
//   widgetStatePath    optional file with the current widget name
//   dockWidgetName     widget name that hides the island entirely
//   widgetRectProvider function(name, sw, sh, uiScale) -> { x, y, w, h } | null
//   widgetList         [{ id, label, icon }] shown in the click dock
//   widgetLauncher     function(id) called when a dock card is clicked
//
// Behaviour:
//   - Pupils track the cursor on Hyprland (hyprctl cursorpos) or through the
//     optional NYX_CURSOR_PROVIDER hook on niri; without a provider they idle
//     with centred pupils. The offset is proportional to the eye size, so
//     tracking reads at any scale.
//   - Hovering the island surprises the mascots; they calm down on leave.
//   - Clicking the island unfolds a dock with widget miniatures (3 per page);
//     picking one launches it through `widgetLauncher` and the mascots cheer.
//   - Random moods (angry / surprised / happy / sleepy, staggered per mascot)
//     on window open/close (Hyprland socket2 / niri event-stream) and widget
//     open/close; asleep after 30 s idle.
//   - The island fades away while the dock widget is open or any occluder
//     overlaps it, and fades back in afterwards.
//   - Only the island and the open dock capture input; the rest of the
//     surface stays click-through through a two-region mask.
// ═══════════════════════════════════════════════════════════════════════════

Variants {
    id: root
    model: Quickshell.screens

    // ── public API ─────────────────────────────────────────────────────────
    property bool enabled: false
    property var species: "flame"
    property int count: 3
    property real size: 1.0
    property real uiScale: 1.0
    property string position: "top-center"
    property string barPosition: "top"
    property real barThickness: 48
    property string appearance: "island"
    property real notchWidth: 260
    property real notchHeight: 0
    property real notchOffset: 0
    property bool notchReserve: true
    property string dockSize: "large"
    property real dockWidth: 0
    property string dockStyle: "floating"
    property int dockColumns: 5
    property int dockRows: 2
    property bool dockShowHero: true
    property bool dockShowQuick: true
    property bool dockShowSearch: true
    property var quickActions: []
    property var quickHandler: null
    property var stats: []
    property var favorites: []
    signal favoriteToggled(string id)
    property string watcherFormat: "24"
    property bool watcherSeconds: true
    property real watcherSpeed: 1.0
    property bool watcherMoods: true
    property bool watcherEye: false
    readonly property var watcherOptions: ({
        format: root.watcherFormat,
        seconds: root.watcherSeconds,
        speed: root.watcherSpeed,
        moods: root.watcherMoods,
        eye: root.watcherEye
    })
    property var palette: ({
        base: "#1e1e2e", surface1: "#45475a", text: "#cdd6f4",
        crust: "#11111b", red: "#f38ba8", yellow: "#f9e2af",
        green: "#a6e3a1", blue: "#89b4fa", mauve: "#cba6f7",
        glassOn: false
    })
    property string settingsPath: ""
    property string widgetStatePath: ""
    property string dockWidgetName: ""
    property var widgetRectProvider: null
    property var widgetList: []
    property var widgetLauncher: null
    // Discovered mascot species (injected by the host). Each item is
    // { id, label, icon, entry?, builtin?, _base }. The lineup resolves ids
    // from this catalog; a custom id carries an "entry" QML file to load.
    property var mascotCatalog: []
    // Per-species options from settings → mascots.options.<id>, injected per
    // mascot through the `options` contract (color, size, …).
    property var speciesOptions: ({})

    // ── compositor awareness ───────────────────────────────────────────────
    // niri has no IPC for the global pointer position, so cursor tracking
    // needs an optional external provider there; niri window events arrive on
    // `niri msg --json event-stream`. Detection is session-wide, not
    // per-screen, so it lives on the root object. NIRI_SOCKET is checked too:
    // some niri sessions do not export "niri" in XDG_CURRENT_DESKTOP.
    readonly property string compositor: String(Quickshell.env("XDG_CURRENT_DESKTOP") || "").toLowerCase()
    readonly property string niriSocket: String(Quickshell.env("NIRI_SOCKET") || "")
    readonly property bool isNiri: compositor.indexOf("niri") !== -1 || niriSocket !== ""
    readonly property string cursorProvider: String(Quickshell.env("NYX_CURSOR_PROVIDER") || "")

    delegate: Component {
        PanelWindow {
            id: overlay

            required property var modelData
            screen: modelData

            // ── derived config ─────────────────────────────────────────────
            // Mascots: a catalog-driven lineup. `species` is a string (all
            // mascots that kind, or "mixed") or an array of ids (one mascot
            // each, in order). The host injects `mascotCatalog`; a custom id
            // resolves to its QML `entry` (loaded by Mascot.qml).
            readonly property var mascotCatalogList: (root.mascotCatalog
                && root.mascotCatalog.length !== undefined) ? root.mascotCatalog : []

            function catalogFor(id) {
                for (let i = 0; i < overlay.mascotCatalogList.length; i++)
                    if (overlay.mascotCatalogList[i].id === id) return overlay.mascotCatalogList[i];
                return null;
            }
            function resolveFile(d, rel) {
                if (!rel) return "";
                let e = String(rel);
                if (e.indexOf("://") !== -1) return e;
                if (e.charAt(0) === "/") return "file://" + e;
                let base = (d && d._base) ? String(d._base) : "";
                return base !== "" ? "file://" + base + "/" + e : e;
            }
            function entryUrl(d) { return resolveFile(d, d ? d.entry : ""); }
            function mascotOptions(id) {
                let o = (root.speciesOptions && root.speciesOptions[id]) ? root.speciesOptions[id] : {};
                if (id === "watcher") o = Object.assign({}, root.watcherOptions, o);
                return o;
            }
            readonly property var speciesLineup: {
                let s = root.species;
                let ids;
                if (Array.isArray(s)) {
                    ids = s.filter(function (x) {
                        return x !== undefined && x !== null && String(x) !== "";
                    });
                } else {
                    let v = String(s === undefined || s === null ? "flame" : s).toLowerCase();
                    if (v === "mixed") ids = ["cat", "dog", "eyes"];
                    else {
                        let n = Math.max(1, Math.min(8, Math.round(root.count)));
                        ids = [];
                        for (let i = 0; i < n; i++) ids.push(v);
                    }
                }
                let out = [];
                for (let i = 0; i < ids.length && i < 8; i++) {
                    let id = String(ids[i]).toLowerCase();
                    if (id === "classic") id = "flame";
                    let d = overlay.catalogFor(id);
                    out.push({ id: id, kind: id, entry: d ? overlay.entryUrl(d) : "" });
                }
                if (out.length === 0) out.push({ id: "flame", kind: "flame", entry: "" });
                return out;
            }
            readonly property int mascotCount: overlay.speciesLineup.length
            readonly property real mascotScale: Math.max(0.6, Math.min(1.6, root.size))

            // Position model (same ids as the editor's position pad). Notch
            // mode only makes sense against the top edge, so it pins to top-*.
            readonly property bool notch: String(root.appearance || "island").toLowerCase() === "notch"
            readonly property bool rawLeft: String(root.position).indexOf("-left") !== -1
            readonly property bool rawRight: String(root.position).indexOf("-right") !== -1
            readonly property bool posTop: overlay.notch || String(root.position).indexOf("top-") === 0
            readonly property bool posBottom: !overlay.notch && String(root.position).indexOf("bottom-") === 0
            readonly property bool posLeft: overlay.notch ? overlay.rawLeft : String(root.position).indexOf("-left") !== -1
            readonly property bool posRight: overlay.notch ? overlay.rawRight : String(root.position).indexOf("-right") !== -1
            readonly property bool panelBelow: !overlay.posBottom

            readonly property real boxMargin: overlay.s(14)
            readonly property real edge: overlay.s(14)
            readonly property real panelGap: overlay.s(8)

            // ── island / dock geometry ─────────────────────────────────────
            // One slot per mascot: 3 mascots = 176 design units.
            readonly property real pillW: (overlay.s(48) * overlay.mascotCount + overlay.s(32))
                * overlay.mascotScale
            readonly property real pillH: overlay.s(46) * overlay.mascotScale
            readonly property real panelW: overlay.popoverId !== ""
                ? overlay.popoverContentW : dockPanel.panelWidth
            readonly property real panelH: overlay.popoverId !== ""
                ? overlay.popoverContentH : dockPanel.panelHeight
            readonly property real popoverContentW: (popoverLoader.item && popoverLoader.item.implicitWidth > 0)
                ? popoverLoader.item.implicitWidth : overlay.s(320)
            readonly property real popoverContentH: (popoverLoader.item && popoverLoader.item.implicitHeight > 0)
                ? popoverLoader.item.implicitHeight : overlay.s(180)
            readonly property real panelShown: Math.max(0, dockPanel.reveal, overlay.popoverReveal)
            readonly property real panelSpan: overlay.panelShown * (overlay.panelGap + overlay.panelH)
            // The layer surface must never be resized by the reveal: even a
            // single resize at the end of a close makes the compositor stretch
            // the previous buffer (the notch appears to stretch after the
            // panel is already gone). Keep edge-anchored overlays at a fixed
            // panel height and clip the content inside; the mask keeps the
            // empty area click-through. Centred positions keep the coupled
            // layout.
            readonly property bool dockHeld: overlay.panelOpen || dockPanel.reveal > 0.001
            readonly property real panelLayoutSpan: {
                if (!(overlay.posTop || overlay.posBottom)) return overlay.panelSpan;
                return overlay.panelGap + dockPanel.panelHeight;
            }
            readonly property real slotW: Math.max(overlay.notch ? overlay.notchW : overlay.pillW,
                overlay.panelW)

            // ── notch geometry ─────────────────────────────────────────────
            readonly property real surfaceW: overlay.screen ? overlay.screen.width : 1920
            // Actual surface width. When the shell frame reserves left/right,
            // the compositor shrinks this full-width (reserveSpace) surface, so
            // screen.width is wrong for layout; overlay.width is the real size.
            readonly property real contentW: overlay.width > 1 ? overlay.width : overlay.surfaceW
            readonly property real notchH: root.notchHeight > 0
                ? Math.max(overlay.pillH + overlay.s(6), overlay.s(root.notchHeight))
                : Math.max(overlay.pillH + overlay.s(10), overlay.s(38))
            readonly property real notchMinW: overlay.pillW + overlay.s(20)
            readonly property real dockPanelW: {
                if (root.dockWidth > 0)
                    return Math.min(overlay.s(root.dockWidth), overlay.contentW * 0.72);
                let preset = String(root.dockSize || "large").toLowerCase();
                let base = preset === "compact" ? 560 : preset === "medium" ? 720
                    : preset === "wide" ? 1200 : 900;
                return Math.min(overlay.s(base), overlay.contentW * 0.72);
            }
            readonly property bool dockJoined: String(root.dockStyle || "floating").toLowerCase() === "joined"
            // While a joined dock is open the notch widens to match it and the
            // bottom corners square off, so the two read as one surface.
            readonly property bool joinedOpen: overlay.dockJoined && overlay.dockHeld
            readonly property real baseNotchW: {
                let maxW = overlay.contentW * 0.5;
                let want = overlay.s(Math.max(80, root.notchWidth));
                return Math.max(overlay.notchMinW, Math.min(maxW, want));
            }
            readonly property real joinedW: Math.min(overlay.contentW * 0.9,
                Math.max(overlay.baseNotchW, overlay.dockPanelW))
            readonly property real notchW: {
                if (!overlay.joinedOpen) return overlay.baseNotchW;
                if (!overlay.reserveSpace) return overlay.joinedW;
                // Full-width surface: follow the dock reveal so the notch
                // contracts with the panel instead of snapping after it is
                // already closed.
                return overlay.baseNotchW
                    + (overlay.joinedW - overlay.baseNotchW) * dockPanel.reveal;
            }
            readonly property real notchRadius: overlay.joinedOpen
                ? (overlay.reserveSpace ? overlay.s(13) * (1 - dockPanel.reveal) : 0)
                : overlay.s(13)
            readonly property real notchY: overlay.s(root.notchOffset)
            readonly property real chromeW: overlay.notch ? overlay.notchW : overlay.pillW
            readonly property real chromeH: overlay.notch ? overlay.notchH : overlay.pillH
            // A notch can reserve the top strip; that needs a full-width surface
            // (three anchors), so the content is laid out against the surface's
            // real width (which the compositor may shrink by other struts).
            readonly property bool reserveSpace: overlay.notch && root.notchReserve
                && root.enabled
            readonly property real layoutW: overlay.reserveSpace ? overlay.contentW : overlay.implicitWidth
            readonly property real notchX: overlay.posLeft ? overlay.boxMargin
                : overlay.posRight ? (overlay.layoutW - overlay.notchW - overlay.boxMargin)
                : Math.round((overlay.layoutW - overlay.notchW) / 2)
            readonly property real chromeX: overlay.notch ? overlay.notchX : overlay.frameX

            implicitWidth: overlay.slotW + overlay.boxMargin * 2
            implicitHeight: overlay.boxMargin * 2 + overlay.chromeH + overlay.panelLayoutSpan
            readonly property real frameX: overlay.posLeft ? overlay.boxMargin
                : overlay.posRight ? (overlay.layoutW - overlay.pillW - overlay.boxMargin)
                : Math.round((overlay.layoutW - overlay.pillW) / 2)
            readonly property real frameY: overlay.notch ? overlay.notchY
                : overlay.boxMargin + (overlay.panelBelow ? 0 : overlay.panelLayoutSpan)
            readonly property real panelX: Math.round(Math.max(0, Math.min(
                overlay.layoutW - overlay.panelW,
                overlay.chromeX + overlay.chromeW / 2 - overlay.panelW / 2)))
            readonly property real panelY: overlay.panelBelow
                ? overlay.frameY + overlay.chromeH + (overlay.dockJoined ? 0 : overlay.panelGap)
                : (overlay.posTop || overlay.posBottom)
                    ? overlay.frameY - (overlay.dockJoined ? 0 : overlay.panelGap) - overlay.panelH
                    : overlay.boxMargin
            // Screen-space origin of this surface (anchored edges have no
            // left/top margin, so the window top-left is computed instead).
            // When reserveSpace, the compositor centres the shrunk surface, so
            // the origin is half the horizontal loss.
            readonly property real originX: overlay.reserveSpace
                ? Math.max(0, Math.round((overlay.surfaceW - overlay.contentW) / 2))
                : (overlay.posRight
                    ? (overlay.screen ? overlay.screen.width - overlay.implicitWidth
                        - overlay.margins.right : 0)
                    : overlay.margins.left)
            readonly property real originY: overlay.posBottom
                ? (overlay.screen ? overlay.screen.height - overlay.implicitHeight
                    - overlay.margins.bottom : 0)
                : overlay.margins.top

            anchors.top: !overlay.posBottom
            anchors.bottom: overlay.posBottom
            anchors.left: !overlay.posRight || overlay.reserveSpace
            anchors.right: overlay.posRight || overlay.reserveSpace
            margins.top: overlay.notch ? 0
                : (!overlay.posBottom
                    ? Math.max(0, Math.round((overlay.posTop
                        ? (overlay.barPosition === "top"
                            ? overlay.s(overlay.barThickness) + overlay.s(14) : overlay.s(14))
                        : (overlay.screen.height - overlay.implicitHeight) / 2) - overlay.boxMargin))
                    : 0)
            margins.bottom: overlay.posBottom
                ? Math.max(0, Math.round((overlay.barPosition === "bottom"
                    ? overlay.s(overlay.barThickness) + overlay.s(14) : overlay.s(14))
                    - overlay.boxMargin))
                : 0
            // Reserving spans the whole top edge (no horizontal margins); the
            // content itself is centred. Otherwise centre the island window.
            margins.left: overlay.reserveSpace ? 0
                : (overlay.posLeft ? Math.max(0, overlay.edge - overlay.boxMargin)
                    : overlay.posRight ? 0
                    : Math.max(0, Math.round((overlay.screen.width - overlay.implicitWidth) / 2)))
            margins.right: overlay.reserveSpace ? 0
                : (overlay.posRight ? Math.max(0, overlay.edge - overlay.boxMargin) : 0)

            color: "transparent"
            WlrLayershell.namespace: "qs-mascots"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: overlay.reserveSpace ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: overlay.reserveSpace ? Math.round(overlay.notchH) : 0
            focusable: false

            // Input mask: the chrome (island / notch) always, the dock while it
            // is unfolded. In notch mode a flush rectangle is used (the rounded
            // bottom corners only clip a few idle pixels).
            mask: Region {
                Region {
                    x: Math.round(overlay.notch ? overlay.chromeX : overlay.chromeX - overlay.s(2))
                    y: Math.round(overlay.notch ? 0 : overlay.frameY - overlay.s(2))
                    width: overlay.chromeShown
                        ? Math.round(overlay.chromeW + overlay.s(4)) : 0
                    height: overlay.chromeShown
                        ? Math.round(overlay.chromeH + overlay.s(4)) : 0
                    radius: overlay.notch ? 0 : Math.round(overlay.pillH / 2 + overlay.s(2))
                }
                Region {
                    x: Math.round(overlay.panelX)
                    y: Math.round(overlay.panelBelow
                        ? overlay.panelY
                        : overlay.panelY + overlay.panelH * (1 - overlay.panelShown))
                    width: overlay.panelShown > 0.001 ? Math.round(overlay.panelW) : 0
                    height: overlay.panelShown > 0.001
                        ? Math.round(overlay.panelH * overlay.panelShown) : 0
                    radius: overlay.s(14)
                }
            }

            // ── scale ──────────────────────────────────────────────────────
            readonly property real baseScale: Metrics.getScale(
                overlay.screen ? overlay.screen.width : 1920,
                overlay.screen ? overlay.screen.height : 1080,
                root.uiScale)
            function s(v) { return Metrics.s(v, overlay.baseScale) }

            // ── settings.json adapter (optional) ───────────────────────────
            function applySettings(txt) {
                try {
                    let p = JSON.parse(txt);
                    let m = (p.mascots && typeof p.mascots === "object") ? p.mascots : {};
                    if (m.enabled !== undefined) root.enabled = m.enabled === true;
                    if (m.size !== undefined) root.size = m.size;
                    if (m.species !== undefined) root.species = m.species;
                    if (m.count !== undefined) root.count = m.count;
                    root.speciesOptions = (m.options && typeof m.options === "object") ? m.options : {};
                    if (m.position !== undefined) root.position = m.position;
                    if (m.appearance !== undefined) root.appearance = String(m.appearance);
                    if (m.notchWidth !== undefined) root.notchWidth = m.notchWidth;
                    if (m.notchHeight !== undefined) root.notchHeight = m.notchHeight;
                    if (m.notchOffset !== undefined) root.notchOffset = m.notchOffset;
                    if (m.notchReserve !== undefined) root.notchReserve = m.notchReserve === true;
                    let d = (m.dock && typeof m.dock === "object") ? m.dock : {};
                    if (d.size !== undefined) root.dockSize = String(d.size);
                    if (d.width !== undefined) root.dockWidth = d.width;
                    if (d.style !== undefined) root.dockStyle = String(d.style);
                    if (d.columns !== undefined) root.dockColumns = Math.max(2, Math.min(8, Math.round(d.columns)));
                    if (d.rows !== undefined) root.dockRows = Math.max(1, Math.min(4, Math.round(d.rows)));
                    if (d.hero !== undefined) root.dockShowHero = d.hero === true;
                    if (d.quick !== undefined) root.dockShowQuick = d.quick === true;
                    if (d.search !== undefined) root.dockShowSearch = d.search === true;
                    let w = (m.watcher && typeof m.watcher === "object") ? m.watcher : {};
                    if (w.format !== undefined) root.watcherFormat = String(w.format);
                    if (w.seconds !== undefined) root.watcherSeconds = w.seconds === true;
                    if (w.speed !== undefined) root.watcherSpeed = w.speed;
                    if (w.moods !== undefined) root.watcherMoods = w.moods === true;
                    if (w.eye !== undefined) root.watcherEye = w.eye === true;
                    if (p.uiScale !== undefined) root.uiScale = p.uiScale;
                    let b = p.bar || {};
                    if (b.position) root.barPosition = b.position;
                    if (b.thickness) root.barThickness = b.thickness;
                } catch (e) {}
            }
            Loader {
                active: root.settingsPath !== ""
                sourceComponent: settingsAdapter
            }
            Component {
                id: settingsAdapter
                Item {
                    Process {
                        id: settingsCat
                        command: ["cat", root.settingsPath]
                        running: true
                        stdout: StdioCollector {
                            onStreamFinished: overlay.applySettings(this.text)
                        }
                    }
                    FileView {
                        path: root.settingsPath
                        watchChanges: true
                        blockLoading: true
                        onFileChanged: settingsCat.running = true
                    }
                }
            }

            // ── widget occlusion (optional, injected) ──────────────────────
            property string currentWidget: ""
            readonly property bool dockOpen: overlay.currentWidget !== ""
                && overlay.currentWidget === root.dockWidgetName
            function widgetOverlaps() {
                if (overlay.currentWidget === "" || overlay.currentWidget === "hidden"
                    || overlay.currentWidget === root.dockWidgetName) return false;
                if (!root.widgetRectProvider) return false;
                let t = null;
                try {
                    t = root.widgetRectProvider(overlay.currentWidget,
                        overlay.screen ? overlay.screen.width : 1920,
                        overlay.screen ? overlay.screen.height : 1080,
                        root.uiScale);
                } catch (e) { t = null; }
                if (!t) return false;
                let m = overlay.s(12);
                let ax = (overlay.screen ? overlay.screen.x : 0) + overlay.originX
                    + overlay.chromeX - m;
                let ay = (overlay.screen ? overlay.screen.y : 0) + overlay.originY
                    + overlay.frameY - m;
                let aw = overlay.chromeW + 2 * m;
                let ah = overlay.chromeH + 2 * m;
                let bx = t.x !== undefined ? t.x : 0;
                let by = t.y !== undefined ? t.y : 0;
                return !(bx + t.w < ax || bx > ax + aw || by + t.h < ay || by > ay + ah);
            }
            readonly property bool blocked: overlay.dockOpen || overlay.widgetOverlaps()
            readonly property bool shown: root.enabled && !overlay.blocked
            // The notch retracts into the floating dock while it is open; a
            // joined dock keeps it visible because they merge into one surface.
            readonly property bool chromeShown: overlay.shown
                && !(overlay.notch && overlay.panelOpen && !overlay.dockJoined)
            readonly property bool mascotsShown: overlay.chromeShown && !overlay.dockHeld

            Loader {
                active: root.widgetStatePath !== ""
                sourceComponent: widgetAdapter
            }
            Component {
                id: widgetAdapter
                Item {
                    Process {
                        id: widgetCat
                        command: ["cat", root.widgetStatePath]
                        running: false
                        stdout: StdioCollector {
                            onStreamFinished: overlay.applyWidget(this.text.trim())
                        }
                    }
                    FileView {
                        path: root.widgetStatePath
                        watchChanges: true
                        blockLoading: true
                        onFileChanged: widgetCat.running = true
                    }
                    Component.onCompleted: widgetCat.running = true
                }
            }
            function applyWidget(name) {
                let prev = overlay.currentWidget;
                if (name === prev) return;
                overlay.currentWidget = name;
                let opened = name !== "" && name !== "hidden";
                let closed = prev !== "" && prev !== "hidden" && !opened;
                if (opened || closed) {
                    overlay.react();
                    idleTimer.restart();
                }
            }

            // ── dock panel ─────────────────────────────────────────────────
            property bool panelOpen: false
            function togglePanel() { overlay.closePopover(); overlay.panelOpen = !overlay.panelOpen; }
            function launchWidget(id) {
                overlay.panelOpen = false;
                overlay.setAllMoods("happy");
                if (root.widgetLauncher) root.widgetLauncher(id);
            }

            // ── per-mascot popover (shares the dock's panel slot/mask) ─────
            // popoverId stays set through the close animation so the panel
            // geometry couples to the real size while it shrinks.
            property bool popoverOpen: false
            property string popoverId: ""
            property real popoverReveal: overlay.popoverOpen ? 1 : 0
            Behavior on popoverReveal { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            onPopoverRevealChanged: {
                if (!overlay.popoverOpen && overlay.popoverReveal < 0.01) overlay.popoverId = "";
            }
            function openPopover(id) { overlay.panelOpen = false; overlay.popoverId = String(id); overlay.popoverOpen = true; }
            function closePopover() { overlay.popoverOpen = false; }
            function togglePopover(id) {
                if (overlay.popoverOpen && overlay.popoverId === String(id)) overlay.closePopover();
                else overlay.openPopover(id);
            }
            function selectedOptions() { return overlay.mascotOptions(overlay.popoverId); }
            // Click on the island: the mascot under the pointer opens its
            // popover if its manifest declares one; otherwise the dock. While a
            // popover is open, any island click collapses it.
            function islandClicked(localX) {
                if (overlay.popoverOpen) { overlay.closePopover(); return; }
                let n = overlay.mascotCount;
                if (n < 1) { overlay.togglePanel(); return; }
                let i = Math.max(0, Math.min(n - 1, Math.floor(localX / (overlay.chromeW / n))));
                let item = overlay.speciesLineup[i];
                let d = item ? overlay.catalogFor(item.id) : null;
                if (d && d.popover) overlay.togglePopover(item.id);
                else overlay.togglePanel();
            }

            // ── cursor ─────────────────────────────────────────────────────
            // Hyprland: hyprctl cursorpos in a loop. niri: no global pointer
            // IPC exists, so only an optional provider (NYX_CURSOR_PROVIDER)
            // is polled and the default is idle pupils.
            property real cursorX: 0
            property real cursorY: 0
            property bool cursorHere: false
            Process {
                id: cursorProc
                command: ["bash", "-c", "while true; do hyprctl cursorpos 2>/dev/null; sleep 0.06; done"]
                running: root.enabled && !root.isNiri
                stdout: SplitParser { onRead: data => overlay.updateCursor(data) }
            }
            Process {
                id: niriCursorProc
                command: ["bash", "-c", root.cursorProvider]
                running: root.enabled && root.isNiri && root.cursorProvider !== ""
                stdout: SplitParser { onRead: data => overlay.updateCursor(data) }
            }
            function updateCursor(line) {
                let p = String(line).split(",");
                if (p.length < 2) return;
                let x = parseFloat(p[0]);
                let y = parseFloat(p[1]);
                if (isNaN(x) || isNaN(y)) return;
                let sx = overlay.screen ? overlay.screen.x : 0;
                let sy = overlay.screen ? overlay.screen.y : 0;
                overlay.cursorX = x;
                overlay.cursorY = y;
                let sw = overlay.screen ? overlay.screen.width : overlay.width;
                let sh = overlay.screen ? overlay.screen.height : overlay.height;
                overlay.cursorHere = x >= sx && x < sx + sw && y >= sy && y < sy + sh;
                if (overlay.cursorHere) idleTimer.restart();
            }

            // ── window events ──────────────────────────────────────────────
            // Hyprland streams raw socket2 lines; niri streams one JSON object
            // per line from `niri msg --json event-stream`.
            Process {
                id: eventsProc
                command: ["bash", "-c",
                    "SOCK=\"${XDG_RUNTIME_DIR:-/tmp}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock\"; " +
                    "while true; do socat -u UNIX-CONNECT:$SOCK - 2>/dev/null; sleep 0.5; done"]
                running: root.enabled && !root.isNiri
                stdout: SplitParser { onRead: data => overlay.handleEvent(data) }
            }
            Process {
                id: niriEventsProc
                command: ["bash", "-c", "niri msg --json event-stream 2>/dev/null"]
                running: root.enabled && root.isNiri
                stdout: SplitParser { onRead: data => overlay.niriHandleEvent(data) }
            }
            function handleEvent(line) {
                let s = String(line);
                if (s.indexOf("openwindow>>") === 0 || s.indexOf("closewindow>>") === 0) {
                    overlay.react();
                } else if (s.indexOf("activewindow>>") === 0) {
                    overlay.pickMood(Math.floor(Math.random() * overlay.mascotCount));
                }
                idleTimer.restart();
            }
            function niriHandleEvent(line) {
                let s = String(line);
                if (s.indexOf("WindowOpenedOrChanged") !== -1
                    || s.indexOf("WindowClosed") !== -1) {
                    overlay.react();
                } else if (s.indexOf("WindowFocusChanged") !== -1) {
                    overlay.pickMood(Math.floor(Math.random() * overlay.mascotCount));
                }
                idleTimer.restart();
            }

            // ── moods (per mascot, staggered random reactions) ──────────────
            property var moods: ["idle", "idle", "idle"]
            function setAllMoods(m) {
                let arr = [];
                for (let i = 0; i < overlay.mascotCount; i++) arr.push(m);
                overlay.moods = arr;
            }
            function pickMood(i) {
                let pool = ["angry", "surprised", "angry", "surprised", "happy", "sleepy"];
                let m = pool[Math.floor(Math.random() * pool.length)];
                let arr = overlay.moods.slice();
                arr[i] = m;
                overlay.moods = arr;
                moodTimer.restart();
            }
            function react() {
                let timers = [reactTimer0, reactTimer1, reactTimer2];
                for (let i = 0; i < overlay.mascotCount; i++) {
                    let t = timers[i];
                    if (t) { t.interval = 60 + Math.round(Math.random() * 320); t.restart(); }
                }
            }
            function hoverReaction(on) {
                if (on) {
                    overlay.setAllMoods("surprised");
                    idleTimer.restart();
                } else {
                    overlay.setAllMoods("idle");
                }
            }
            Timer { id: reactTimer0; onTriggered: overlay.pickMood(0) }
            Timer { id: reactTimer1; onTriggered: overlay.pickMood(1) }
            Timer { id: reactTimer2; onTriggered: overlay.pickMood(2) }
            Timer {
                id: moodTimer
                interval: 1700
                onTriggered: overlay.setAllMoods("idle")
            }
            Timer {
                id: idleTimer
                interval: 30000
                onTriggered: overlay.setAllMoods("sleepy")
            }

            // Dominant mood drives the island accent line.
            readonly property string dominantMood: {
                let prio = ["angry", "surprised", "happy", "sleepy"];
                for (let p = 0; p < prio.length; p++)
                    for (let i = 0; i < overlay.moods.length; i++)
                        if (overlay.moods[i] === prio[p]) return prio[p];
                return "idle";
            }
            readonly property color accentColor: dominantMood === "angry" ? root.palette.red
                : dominantMood === "surprised" ? root.palette.yellow
                : dominantMood === "happy" ? root.palette.green
                : dominantMood === "sleepy" ? root.palette.blue
                : root.palette.mauve

            // ── mascot slots ───────────────────────────────────────────────
            readonly property real mascotSize: overlay.s(30) * overlay.mascotScale
            readonly property real zSize: overlay.s(11) * overlay.mascotScale
            property real clock: 0
            property var mpos: [
                { x: 30, y: 10, px: 0, py: 0 },
                { x: 90, y: 10, px: 0, py: 0 },
                { x: 150, y: 10, px: 0, py: 0 }
            ]

            Timer {
                interval: 16
                repeat: true
                running: root.enabled && overlay.mascotsShown
                onTriggered: overlay.step()
            }

            function step() {
                overlay.clock += 1;
                let n = overlay.mascotCount;
                let arr = [];
                let sx = overlay.screen ? overlay.screen.x : 0;
                let sy = overlay.screen ? overlay.screen.y : 0;
                let lx = overlay.cursorX - sx;
                let ly = overlay.cursorY - sy;
                for (let i = 0; i < n; i++) {
                    let cur = overlay.mpos[i] || { x: overlay.frameX + i * 40, y: overlay.frameY, px: 0, py: 0 };
                    let tx = overlay.chromeX + overlay.chromeW * (i + 0.5) / n - overlay.mascotSize / 2;
                    let ty = overlay.frameY + overlay.chromeH / 2 - overlay.mascotSize * 0.55;
                    let nx = cur.x + (tx - cur.x) * 0.13;
                    let ny = cur.y + (ty - cur.y) * 0.13;
                    // Look direction: unit vector from the mascot centre in
                    // SCREEN coordinates to the cursor (the window margins are
                    // part of the screen position; without them the eyes only
                    // track one half of the screen). Smoothed per tick.
                    let tpx = 0, tpy = 0;
                    if (overlay.cursorHere) {
                        let cxp = overlay.originX + nx + overlay.mascotSize / 2;
                        let cyp = overlay.originY + ny + overlay.mascotSize / 2;
                        let vx = lx - cxp, vy = ly - cyp;
                        let d = Math.max(1, Math.sqrt(vx * vx + vy * vy));
                        tpx = vx / d;
                        tpy = vy / d;
                    }
                    let px = (cur.px || 0) + (tpx - (cur.px || 0)) * 0.28;
                    let py = (cur.py || 0) + (tpy - (cur.py || 0)) * 0.28;
                    arr.push({ x: nx, y: ny, px: px, py: py });
                }
                overlay.mpos = arr;
            }

            // ── island / notch ─────────────────────────────────────────────
            Rectangle {
                id: frame
                x: overlay.chromeX
                y: overlay.frameY
                width: overlay.chromeW
                height: overlay.chromeH
                radius: overlay.notch ? 0 : height / 2
                visible: opacity > 0.01
                opacity: overlay.chromeShown ? 1.0 : 0.0
                scale: overlay.chromeShown ? 1.0 : 0.78
                color: overlay.notch ? "transparent"
                    : Qt.rgba(root.palette.base.r, root.palette.base.g,
                              root.palette.base.b,
                              root.palette.glassOn === true
                                  ? Math.min(0.95, root.palette.base.a + 0.05) : 1.0)
                border.width: overlay.notch ? 0 : 1
                border.color: overlay.notch ? "transparent" : Qt.alpha(root.palette.surface1, 0.9)
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                // Notch silhouette: flush with the top edge, concave top fillets
                // and rounded bottom corners, no coloured border.
                Shape {
                    id: notchShape
                    anchors.fill: parent
                    visible: overlay.notch
                    ShapePath {
                        strokeWidth: 0
                        fillColor: Qt.rgba(root.palette.base.r, root.palette.base.g,
                                           root.palette.base.b,
                                           root.palette.glassOn === true
                                               ? Math.min(0.95, root.palette.base.a + 0.05) : 1.0)
                        startX: 0
                        startY: overlay.s(9)
                        PathQuad { x: overlay.s(9); y: 0
                            controlX: overlay.s(9); controlY: overlay.s(9) }
                        PathLine { x: frame.width - overlay.s(9); y: 0 }
                        PathQuad { x: frame.width; y: overlay.s(9)
                            controlX: frame.width - overlay.s(9); controlY: overlay.s(9) }
                        PathLine { x: frame.width; y: frame.height - overlay.notchRadius }
                        PathArc { x: frame.width - overlay.notchRadius; y: frame.height
                            radiusX: overlay.notchRadius; radiusY: overlay.notchRadius
                            direction: PathArc.Clockwise }
                        PathLine { x: overlay.notchRadius; y: frame.height }
                        PathArc { x: 0; y: frame.height - overlay.notchRadius
                            radiusX: overlay.notchRadius; radiusY: overlay.notchRadius
                            direction: PathArc.Clockwise }
                        PathLine { x: 0; y: overlay.s(9) }
                    }
                }

                Rectangle {
                    visible: !overlay.notch
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius - 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(overlay.accentColor, 0.45)
                    Behavior on border.color { ColorAnimation { duration: 250 } }
                }
                // palette accent line (state colour)
                Rectangle {
                    visible: !overlay.joinedOpen
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: overlay.s(7)
                    width: parent.width * 0.22
                    height: overlay.s(3)
                    radius: height / 2
                    color: overlay.accentColor
                    Behavior on color { ColorAnimation { duration: 250 } }
                }
                // Click / hover (the pointer only reaches this surface inside
                // the island mask region).
                MouseArea {
                    id: islandMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => overlay.islandClicked(mouse.x)
                    onEntered: overlay.hoverReaction(true)
                    onExited: overlay.hoverReaction(false)
                }
            }

            // ── widget dock (unfolds from the island) ──────────────────────
            MascotDock {
                id: dockPanel
                x: overlay.panelX
                y: overlay.panelBelow ? overlay.panelY
                    : overlay.panelY + overlay.panelH * (1 - dockPanel.reveal)
                width: overlay.panelW
                height: overlay.panelH * dockPanel.reveal
                open: overlay.panelOpen
                widgets: root.widgetList
                quickActions: root.quickActions
                stats: root.stats
                favorites: root.favorites
                panelWidth: overlay.dockPanelW
                joined: overlay.dockJoined
                unfoldUp: !overlay.panelBelow
                columns: root.dockColumns
                rows: root.dockRows
                showHero: root.dockShowHero
                showQuick: root.dockShowQuick
                showSearch: root.dockShowSearch
                palette: root.palette
                scaleUnit: overlay.baseScale
                accent: overlay.accentColor
                onLaunchRequested: (id) => overlay.launchWidget(id)
                onQuickRequested: (id) => {
                    if (root.quickHandler) root.quickHandler(id);
                    else overlay.launchWidget(id);
                }
                onFavoriteToggled: (id) => root.favoriteToggled(id)
                onCloseRequested: overlay.panelOpen = false
            }

            // ── per-mascot popover (shares the dock's panel slot) ──────────
            // The host grows/shrinks with the reveal (like the dock) and clips
            // its content: the content is never scaled, so closing cannot
            // stretch it. Both edges stay anchored to the island.
            Item {
                id: popoverHost
                x: overlay.panelX
                y: overlay.panelBelow ? overlay.panelY
                    : overlay.panelY + overlay.panelH * (1 - overlay.popoverReveal)
                width: overlay.panelW
                height: Math.max(0, overlay.panelH * overlay.popoverReveal)
                clip: true
                visible: overlay.popoverReveal > 0.01

                Rectangle {
                    id: popoverBg
                    width: parent.width
                    height: Math.max(0, overlay.panelH * overlay.popoverReveal)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: overlay.panelBelow ? parent.top : undefined
                    anchors.bottom: overlay.panelBelow ? undefined : parent.bottom
                    radius: overlay.s(14)
                    color: Qt.rgba(root.palette.base.r, root.palette.base.g, root.palette.base.b,
                        root.palette.glassOn === true ? 0.9 : 1.0)
                    border.width: 1
                    border.color: Qt.alpha(root.palette.surface1, 0.9)
                }

                Loader {
                    id: popoverLoader
                    width: parent.width
                    height: overlay.panelH
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: overlay.panelBelow ? 0 : (popoverHost.height - overlay.panelH)
                    opacity: overlay.popoverReveal
                    source: {
                        if (overlay.popoverId === "") return "";
                        let d = overlay.catalogFor(overlay.popoverId);
                        return d && d.popover ? overlay.resolveFile(d, d.popover) : "";
                    }
                    onLoaded: {
                        if (!item) return;
                        try { item.closeRequested.connect(() => overlay.closePopover()); } catch (e) {}
                    }
                }
                Binding { target: popoverLoader.item; property: "options";   value: overlay.selectedOptions() }
                Binding { target: popoverLoader.item; property: "palette";   value: root.palette }
                Binding { target: popoverLoader.item; property: "scaleUnit"; value: overlay.baseScale }
                Binding { target: popoverLoader.item; property: "accent";    value: overlay.accentColor }
            }

            // ── mascots ────────────────────────────────────────────────────
            Repeater {
                model: overlay.speciesLineup
                delegate: Mascot {
                    required property var modelData
                    required property int index
                    width: overlay.mascotSize
                    height: overlay.mascotSize * 1.18
                    opacity: overlay.mascotsShown ? 1.0 : 0.0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    slot: index
                    species: modelData.kind
                    entry: modelData.entry
                    mood: overlay.moods[index] || "idle"
                    lookX: (overlay.mpos[index] || {}).px || 0
                    lookY: (overlay.mpos[index] || {}).py || 0
                    tint: [root.palette.mauve, root.palette.blue,
                           root.palette.green][index % 3]
                    crust: root.palette.crust
                    text: root.palette.text
                    red: root.palette.red
                    palette: root.palette
                    clock: overlay.clock
                    xPos: (overlay.mpos[index] || {}).x || 0
                    yPos: (overlay.mpos[index] || {}).y || 0
                    zSize: overlay.zSize
                    options: overlay.mascotOptions(modelData.id)
                }
            }
        }
    }
}
