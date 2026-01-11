Config = {}

-- Prop
Config.BoardModel = `prop_w_board_blank`

-- Panel rendering
Config.ResW = 1024
Config.ResH = 1024

-- Fit panel to the writing area using model dimensions (min/max)
-- width = modelWidth * WidthFactor
-- height = modelHeight * HeightFactor
Config.WidthFactor  = 0.94
Config.HeightFactor = 0.72

-- Choose a sampling height (0..1 of model height from min.z to max.z) for the face-raycast
-- and a small upward bias (in meters) to avoid the feet/casters.
Config.SampleZFactor = 0.55
Config.SampleZBias   = 0.08

-- Small push along the face normal so the panel doesn't z-fight (keep tiny)
Config.FaceEpsilon = 0.0010

-- Placement
Config.PlaceDistance = 7.0

-- Preview transparency
Config.PreviewAlpha = 120

-- Controls
Config.KeyPlace = 'E'
Config.KeyTogglePlace = 'F7'
Config.KeyToggleInteract = 'G'



-- Interaction mode
-- 'uv' = raycast/UV world-space interaction (default)
-- 'key2dui' = locked cursor (no UV updates after selecting a panel)
Config.InteractionMode = Config.InteractionMode or 'uv'

-- Key2DUI tuning
Config.Key2DUICursorSpeed = Config.Key2DUICursorSpeed or 0.010  -- cursor speed multiplier
Config.Key2DUIFlipY = (Config.Key2DUIFlipY == true)             -- true = invert Y (if your vertical axis feels flipped)

-- When using key2dui, press ESC or BACKSPACE to exit the cursor mode.
-- Extra vertical nudge (meters) applied along the board's UP vector after face-raycast.
-- Use this to fine-tune if the panel is slightly too low/high.
Config.PanelUpOffset = 0.0
-- =========================================================
-- Performance tuning (optional)
-- =========================================================
-- These defaults are chosen to keep the demo responsive while scaling better
-- when many boards exist in the world. You can tweak them per server.
Config.RenderDistance = Config.RenderDistance or 25.0        -- meters (only process boards within this range)
Config.NearbyCacheInterval = Config.NearbyCacheInterval or 250 -- ms (how often we rebuild nearby board list)
Config.PlayerPosInterval = Config.PlayerPosInterval or 500    -- ms (how often we refresh cached player coords)
Config.RaycastThrottle = Config.RaycastThrottle or 50         -- ms (raycast frequency when not actively drawing)
Config.IdleWait = Config.IdleWait or 100                      -- ms (sleep when idle / no hit)
Config.PlaceIdleWait = Config.PlaceIdleWait or 200            -- ms (sleep when placement mode is off)
