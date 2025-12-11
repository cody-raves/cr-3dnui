# cr-3dnui

> Interactive 3D NUI panels for FiveM – real web apps on in-game screens.

`cr-3dnui` is a developer tool that lets you render live HTML/JS UIs onto walls, props, and surfaces in FiveM and interact with them in 3D using raycasts.

Instead of opening fullscreen NUI, players walk up to a screen in the world, press a key, and click real buttons on a live web page that calls your client/server events.

Use cases include:

- ATMs with real PIN pads  
- PD boards / MDT terminals  
- Hospital check-in kiosks  
- Vending machines, gas pumps, kiosks  
- Arcade machines running HTML/JS games  
- Admin / debug terminals  

---

## What it does

- Renders a live HTML page via DUI using `nui://...` (no screenshots or baked textures)
- Preserves transparency correctly (no black boxes around UI)
- Maps 3D camera ray → panel UV → DOM hit using `elementFromPoint`
- Sends clicks and key events from the world into the page
- Sends actions back to Lua via `RegisterNUICallback`
- Hooks into your framework (e.g. QBCore, qb-weathersync) for real gameplay effects

In the current proof of concept, the client-side runtime sits around ~0.05 ms.

---

## Current proof of concept

The included POC demonstrates:

- A world-space panel you can place on any wall
- A "use" mode (press a key, aim at the screen, click buttons)
- A demo HTML keypad / menu that can:
  - Change time and weather (via qb-weathersync)
  - Add and remove cash
  - Give an item (for example `water_bottle`)
  - Revive the player
  - Spawn a vehicle (`elegy2`)

All interaction happens in-world. There is no fullscreen NUI overlay.

This proves the full pipeline:

> Display → Interact → Call client/server events → Change the game.

---

## High-level flow

1. **Place a panel in the world**  
   - Raycast from the camera to a wall  
   - Store `pos`, `normal`, `scale`

2. **Create a DUI**  
   - Load `nui://your-resource/html/panel.html`  
   - Attach it to a runtime texture

3. **Draw the panel**  
   - Build a quad in 3D from `pos`, `normal`, `width`, `height`  
   - Draw the DUI texture with `DrawSpritePoly`

4. **Interact with the panel**  
   - Raycast from the camera to that quad  
   - Convert hit point → normalized UV (0–1)  
   - Send `{ type = "click", x, y }` into the page  
   - Use `elementFromPoint` inside the page to detect the clicked element  
   - Call back into Lua via `RegisterNUICallback`  
   - Run your own QBCore / framework logic

---

## Vision and roadmap

The goal is to turn `cr-3dnui` into a general 3D UI framework that other resources can consume via exports, for example:

- `exports['cr-3dnui']:CreatePanel({ ... })`  
- `exports['cr-3dnui']:CreateMenuPanel({ info, buttons, onClientAction, onServerAction })`  

Planned features and examples:

- Panel persistence (save `pos`, `normal`, `scale`, `type` to JSON/SQL)
- Example integrations:
  - ATM with PIN and banking UI
  - PD MDT / BOLO / 911 board
  - Arcade cabinets running HTML/JS games
  - Vending machines and gas pumps
  - Radio / DJ control panels

---

## Status

This repository currently contains a working proof of concept and reference implementation of:

- Live DUI rendering of a NUI page
- World-space panel drawing
- 3D raycast → UV → DOM click mapping
- NUI callbacks driving real gameplay events

APIs and structure are subject to change as this evolves into a reusable developer framework.
