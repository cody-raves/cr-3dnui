# cr-3dnui

> Interactive 3D DUI panels for FiveM — real web apps on in-game screens.

`cr-3dnui` is a **developer library** that lets you render live HTML/JS UIs onto walls, props, and surfaces in FiveM and interact with them in 3D using raycasts.

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

- Renders a live HTML page via **DUI** (`CreateDui`) using `nui://...` URLs
- Draws the DUI texture on a **world-space quad** (arbitrary position + normal)
- Converts **camera ray → panel hit → UV (0..1)** via `RaycastPanel()`
- Supports two interaction styles:
  - **Message-based** input (good for menus)
  - **Native mouse injection** (hover/drag, “real” pointer behavior)
- Optional helper: draws a HUD cursor sprite via `DrawCursor()` (your resource decides when)

---

## Included example

This repo ships with an example demo:

- `cr-3dnui_whiteboarddemo/` — a placeable in-world whiteboard that supports:
  - brush drawing (drag)
  - eraser
  - text placement (onscreen keyboard commit)
  - custom font dropdown (DUI-safe)

The demo is meant to be a **reference implementation** showing how to consume the library exports.

---

## Installation

1. Put both folders in your server resources:
   - `cr-3dnui`
   - `cr-3dnui_whiteboarddemo` (optional example)

2. Start order in `server.cfg`:

```cfg
ensure cr-3dnui
ensure cr-3dnui_whiteboarddemo
```

---

## Library exports

All exports are **client-side**.

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

### Raycast a panel

```lua
local hitPos, u, v, t = exports["cr-3dnui"]:RaycastPanel(panelId, 3.0)
-- u/v are normalized 0..1 across the panel surface
-- t is distance along the camera ray
```

### Send input to the DUI

**Message-based click (simple menus):**

```lua
exports["cr-3dnui"]:SendClick(panelId, u, v, { any = "meta" })
```

**Send any custom message (recommended for game logic):**

```lua
exports["cr-3dnui"]:SendMessage(panelId, { type = "my_event", foo = 123 })
```

**Native mouse injection (hover / drag / true pointer behavior):**

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

## Recommended interaction loop (pattern)

A typical “use mode” loop looks like:

1. Choose the best panel (nearest ray hit among your panels)
2. `DisableControlAction` to prevent firing while interacting
3. `SendMouseMove(panelId, u, v)`
4. On click press/release: `SendMouseDown / SendMouseUp`

(Exactly what the whiteboard demo does.)

---

## DUI / FiveM limitations (important)

- **DUI is not fullscreen NUI.** Some “browser UI” features don’t behave the same.
- Native HTML `<select>` dropdowns often don’t work in DUI — use a **custom dropdown** (the demo shows this).
- `GetParentResourceName()` may not exist inside a DUI page depending on context.  
  If your page needs to call `fetch("https://resourceName/callback")`, pass the resource name in the URL query string, e.g.:
  - `nui://my_resource/html/index.html?res=my_resource`

---

## Panel resolution (resW/resH) and why it matters

`cr-3dnui` turns raycast UVs (0..1) into DUI pixel coordinates:

- `px = u * resW`
- `py = v * resH`

So DUI resolution affects:
- **Input precision**: low res can feel “chunky” for hover/click (bigger pixel grid).
- **Visual clarity**: low res looks blurry, especially for small text.
- **Performance**: higher res costs more GPU/texture memory.

### Recommended resolutions

Match the DUI resolution to your **panel aspect ratio** and **UI density**:

- **Simple UI / big buttons**
  - `512×512` (or `512×256`, `256×512`)
- **Most cases (recommended default)**
  - `1024×1024` (or `1024×512`, `512×1024`)
- **Small text / dense UI / “desktop-like” panels**
  - `2048×1024` (or `2048×2048` if square)

### Match aspect ratio

If the panel is wide, use a wide DUI:
- wide panel → `1024×512` or `2048×1024`

If the panel is tall, use a tall DUI:
- tall panel → `512×1024`

Avoid forcing a square DUI onto a wide panel (it stretches UI and makes hit-testing feel off).

### Practical tip

Start at `1024×512` (wide) or `1024×1024` (square). Increase only if:
- hover/click feels “steppy”
- text is hard to read at the intended viewing distance

## Status

This repository contains:

- A working library with exports for:
  - live DUI rendering on world quads
  - raycast → UV mapping
  - message + native mouse injection helpers
- A working whiteboard demo proving:
  - in-world drawing (drag)
  - UI controls (buttons/sliders)
  - DUI-safe dropdown patterns
  - text placement via onscreen keyboard commit

The API will continue evolving as more examples and higher-level helpers are added.

---
