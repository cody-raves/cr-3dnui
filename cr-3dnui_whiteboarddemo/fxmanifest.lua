fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'codyraves'
description 'cr-3dnui_whiteboarddemo: placeable whiteboard with in-world paint UI (cr-3dnui) - face-raycast aligned'
version '1.0.0'

dependency 'cr-3dnui'

-- IMPORTANT: ui_page is blank so nothing overlays on screen
ui_page 'html/blank.html'

files {
  'html/blank.html',
  'html/index.html',
  'html/style.css',
  'html/app.js'
}

client_scripts {
  'config.lua',
  'client/main.lua'
}
