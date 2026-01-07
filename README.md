# cr-3dnui

> Interactive 3D DUI panels for FiveM — real web apps on in-game screens.

`cr-3dnui` is a developer library that lets you render live HTML/JS UIs onto walls, props, surfaces, and entities in FiveM and interact with them in 3D using raycasts.

Instead of opening fullscreen NUI, players walk up to a screen in the world and interact with a web UI that triggers your client/server logic.

Use cases:

- ATMs with PIN pads  
- PD boards / MDT terminals  
- Hospital check-in kiosks  
- Vending machines / gas pumps / kiosks  
- Arcade machines running HTML/JS games  
- Admin / debug terminals  

---

## What it does

- Renders a live HTML page via DUI (`CreateDui`) using `nui://...` URLs
- Draws the DUI texture on a world-space quad (arbitrary position + normal)
- Converts camera ray → panel hit → UV (0..1) via `RaycastPanel()`
- Supports two interaction styles:
  - Message-based input (good for menus)
  - Native mouse injection (hover/drag, real pointer behavior)
- Supports focus + keyboard input forwarding for keyboard-driven UIs (games, terminals, PIN pads)
- Optional helper: draws a HUD cursor sprite via `DrawCursor()` (your resource decides when)
- New helper: `AttachPanelToEntity()` for stable moving-entity panels (vehicles/peds/objects) with centralized transform updates and distance gating

---

## Included examples

This repo ships with example demos:

- `cr-3dnui_whiteboarddemo/` — a placeable in-world whiteboard that supports:
  - brush drawing (drag)
  - eraser
  - text placement (onscreen keyboard commit)
  - custom font dropdown (DUI-safe)

- `cr-3dnui_snakedemo/` — a placeable in-world arcade panel demonstrating:
  - keyboard input capture and forwarding into DUI
  - strict focus mode (blocks GTA/server binds while active)
  - real-time gameplay on a world-space surface
  - ESC exit and auto-disengage when looking away

- `cr-3dnui_cardemo/` — a simple vehicle attachment demo demonstrating:
  - attaching a panel to a moving entity via `AttachPanelToEntity()`
  - stable per-frame attachment updates (`updateInterval = 0`)
  - distance-gated transform updates (`updateMaxDistance`)
  - a minimal “working demo” UI on a car roof

The demos are meant to be a reference implementation showing how to consume the library exports.

Important: Only run one of these two input-capturing demos at a time: `cr-3dnui_whiteboarddemo` and `cr-3dnui_snakedemo`. Both capture inputs (and may share keys like `G` / `F7`), so enabling both can cause conflicting keybind behavior. `cr-3dnui_cardemo` is a simple attachment demo and does not need to capture inputs unless you manually toggle focus (`/nuifocus`).

---

## Installation

1. Put folders in your server resources:
   - `cr-3dnui`
   - `cr-3dnui_whiteboarddemo` (optional example)
   - `cr-3dnui_snakedemo` (optional example)
   - `cr-3dnui_cardemo` (optional example)

2. Start order in `server.cfg` (pick one demo):

```cfg
ensure cr-3dnui

# Choose ONE demo at a time:
ensure cr-3dnui_whiteboarddemo
# ensure cr-3dnui_snakedemo
# ensure cr-3dnui_cardemo
```

---

## cr-3dnui_cardemo usage

The car demo attaches a “working demo” panel to the nearest vehicle or the vehicle you are currently in.

Commands:

- `/nuiroof`  
  Attaches the demo panel to the target vehicle using `AttachPanelToEntity()` with `updateInterval = 0`.

- `/nuioff`  
  Removes the demo panel.

- `/nuifocus` (optional)  
  Toggles focus so you can test input forwarding on the attached panel.

If you do not see the panel, ensure the demo resource is started and that its NUI files are included in the demo resource `fxmanifest.lua` `files { ... }` list (the demo loads `nui://<demo_resource>/ui/index.html`).

---

## Library exports

All exports are client-side.

### Create and manage panels

```lua
local panelId = exports["cr-3dnui"]:CreatePanel({
  id = 1, -- optional, auto-assigned if omitted
  url = "nui://my_resource/html/index.html",
  resW = 1024,
  resH = 1024,
  pos = vector3(0.0, 0.0, 0.0),
  normal = vector3(0.0, 0.0, 1.0),
  width = 1.0,
  height = 1.0,
  alpha = 255,
  enabled = true,
  zOffset = 0.002,
  faceCamera = true
})
```

- `DestroyPanel(panelId)`
- `SetPanelTransform(panelId, pos, normal)`
- `SetPanelSize(panelId, width, height)`
- `SetPanelUrl(panelId, url, resW, resH)`
- `SetPanelAlpha(panelId, alpha)`
- `SetPanelEnabled(panelId, enabled)`

### Attach a panel to an entity (moving vehicles/peds/objects)

`AttachPanelToEntity()` attaches a panel using entity-space placement and centralizes the transform update loop inside the library. This avoids each consumer script running its own 0-tick transform loop and helps prevent stepping/jitter caused by inconsistent update cadence.

```lua
local panelId = exports["cr-3dnui"]:AttachPanelToEntity({
  entity = veh,
  url = "nui://my_resource/ui/index.html",

  resW = 1024,
  resH = 512,

  width = 1.65,
  height = 0.45,
  alpha = 255,
  enabled = true,

  -- Entity-space placement
  localOffset = vector3(0.0, 0.10, 1.70),

  -- Entity-space facing (pick the axis that faces your camera/players)
  -- forward:  vector3(0.0,  1.0, 0.0)
  -- rear:     vector3(0.0, -1.0, 0.0)
  -- right:    vector3(1.0,  0.0, 0.0)
  -- left:     vector3(-1.0, 0.0, 0.0)
  -- up:       vector3(0.0,  0.0, 1.0)
  localNormal = vector3(-1.0, 0.0, 0.0),

  rotateNormal = true,

  -- Update cadence and distance gating
  updateInterval = 0,        -- 0 = per-frame attachment updates (smoothest)
  updateMaxDistance = 110.0  -- skip transform updates when far
})
```

### Raycast a panel

```lua
local hitPos, u, v, t = exports["cr-3dnui"]:RaycastPanel(panelId, 3.0)
-- u/v are normalized 0..1 across the panel surface
-- t is distance along the camera ray
```

### Send input to the DUI

Message-based click (simple menus):

```lua
exports["cr-3dnui"]:SendClick(panelId, u, v, { any = "meta" })
```

Send any custom message (recommended for game logic):

```lua
exports["cr-3dnui"]:SendMessage(panelId, { type = "my_event", foo = 123 })
```

Native mouse injection (hover / drag / true pointer behavior):

```lua
exports["cr-3dnui"]:SendMouseMove(panelId, u, v, { flipY = false })
exports["cr-3dnui"]:SendMouseDown(panelId, "left")
exports["cr-3dnui"]:SendMouseUp(panelId, "left")
exports["cr-3dnui"]:SendMouseWheel(panelId, 120)
```

### Optional HUD cursor helper

```lua
exports["cr-3dnui"]:DrawCursor(0.5, 0.5, true, { w = 0.015, h = 0.03 })
```

You decide when/where to draw it (this library does not force a cursor).

---

## Focus and keyboard input

To support keyboard-driven apps (games, terminals, PIN pads, etc.), `cr-3dnui` provides a focus mode that:

- Raycasts the panel every frame
- Disables GTA/server controls while focused (prevents binds like cover, vehicle locks, etc.)
- Captures key presses using `IsDisabledControlJustPressed`
- Forwards keys into the DUI as `SendDuiMessage` payloads
- Exits cleanly on ESC (and/or custom exit keys) or when you look away

### Begin / end focus

```lua
exports["cr-3dnui"]:BeginFocus(panelId, {
  maxDist = 7.0,
  strict = true,              -- blocks a wider set of GTA controls while focused
  drawCursor = true,          -- draws HUD cursor via library helper (optional)
  autoExitOnMiss = true,      -- exit if you stop looking at / hitting the panel
  missGraceMs = 250,          -- small grace so tiny ray misses don't instantly exit
  exitControls = {200, 177},  -- ESC / BACKSPACE (default)
  allowLook = true,           -- allow camera look while focused (recommended)
  sendFocusMessages = true    -- sends focus_on/focus_off messages to the DUI
})

-- manually end focus (also ends automatically if autoExitOnMiss triggers)
exports["cr-3dnui"]:EndFocus()
```

### Configure which keys to forward

```lua
exports["cr-3dnui"]:SetFocusKeymap({
  { id = 32, key = "W" },
  { id = 33, key = "S" },
  { id = 34, key = "A" },
  { id = 35, key = "D" },
  { id = 172, key = "UP" },
  { id = 173, key = "DOWN" },
  { id = 174, key = "LEFT" },
  { id = 175, key = "RIGHT" },
  { id = 22, key = "SPACE" },
})
```

Keys are forwarded into the DUI as:

```json
{ "type": "key", "key": "W", "code": 32 }
```

And can be handled inside your UI via:

```js
window.addEventListener("message", (e) => {
  const msg = e.data;
  if (msg?.type === "key") {
    // msg.key, msg.code
  }

  if (msg?.type === "focus_on") {
    // optional: show a "focused" state in the UI
  }

  if (msg?.type === "focus_off") {
    // optional: pause, hide cursor, etc.
  }
});
```

---

## Recommended interaction loop (pattern)

A typical use loop looks like:

1. Choose the best panel (nearest ray hit among your panels)
2. Disable controls to prevent firing while interacting
3. `SendMouseMove(panelId, u, v)`
4. On click press/release: `SendMouseDown / SendMouseUp`

(Exactly what the whiteboard demo does.)

---

## DUI / FiveM limitations (important)

- DUI is not fullscreen NUI. Some browser UI features don’t behave the same.
- Native HTML `<select>` dropdowns often don’t work in DUI — use a custom dropdown (the demo shows this).
- `GetParentResourceName()` may not exist inside a DUI page depending on context.
  If your page needs to call `fetch("https://resourceName/callback")`, pass the resource name in the URL query string, e.g.:
  - `nui://my_resource/html/index.html?res=my_resource`

---

## Panel resolution (resW/resH) and why it matters

`cr-3dnui` turns raycast UVs (0..1) into DUI pixel coordinates:

- `px = u * resW`
- `py = v * resH`

So DUI resolution affects:
- Input precision: low res can feel chunky for hover/click (bigger pixel grid).
- Visual clarity: low res looks blurry, especially for small text.
- Performance: higher res costs more GPU/texture memory.

### Recommended resolutions

Match the DUI resolution to your panel aspect ratio and UI density:

- Simple UI / big buttons
  - `512×512` (or `512×256`, `256×512`)
- Most cases (recommended default)
  - `1024×1024` (or `1024×512`, `512×1024`)
- Small text / dense UI / desktop-like panels
  - `2048×1024` (or `2048×2048` if square)

### Match aspect ratio

If the panel is wide, use a wide DUI:
- wide panel → `1024×512` or `2048×1024`

If the panel is tall, use a tall DUI:
- tall panel → `512×1024`

Avoid forcing a square DUI onto a wide panel (it stretches UI and makes hit-testing feel off).

### Practical tip

Start at `1024×512` (wide) or `1024×1024` (square). Increase only if:
- hover/click feels steppy
- text is hard to read at the intended viewing distance

---

# Credit
**Optimizations:** [RobiRoberto](https://github.com/RobiRoberto)  
Original write-up: [Amazing performance optimization report](https://github.com/cody-raves/cr-3dnui/issues/1)


## Status

This repository contains:

- A working library with exports for:
  - live DUI rendering on world quads
  - raycast → UV mapping
  - message + native mouse injection helpers
  - focus + keyboard input forwarding helpers
  - stable moving-entity attachment via `AttachPanelToEntity()`
- Example demos proving:
  - in-world drawing (drag) + UI controls (whiteboard)
  - keyboard-driven gameplay on a world-space arcade panel (snake)
  - moving-entity attachment with per-frame updates and distance gating (car demo)

The API will continue evolving as more examples and higher-level helpers are added.
