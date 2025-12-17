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


-- Extra vertical nudge (meters) applied along the board's UP vector after face-raycast.
-- Use this to fine-tune if the panel is slightly too low/high.
Config.PanelUpOffset = 0.0
