fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'codyraves'
description 'cr-3dnui - Interactive 3D DUI panels (world-space quads) with raycast + focus helpers + entity attachment helper (AttachPanelToEntity) + mouse injection / forwarding + car ROT solved'
version '2.5'

client_scripts {
  'client/config.lua',
  'client/state.lua',

  'client/util/vec.lua',
  'client/util/time.lua',

  'client/render/basis.lua',
  'client/render/draw.lua',

  'client/input/raycast_uv.lua',
  'client/focus/focus.lua',

  'client/main.lua',
}

files {
  'assets/cursor.png'
}
