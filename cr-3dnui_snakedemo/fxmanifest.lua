fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'codyraves'
description 'Snake demo using cr-3dnui focus + keyboard exports'
version '2.1'

dependency 'cr-3dnui'

ui_page 'html/bridge.html'

files {
  'html/bridge.html',
  'html/panel.html',
  'html/style.css',
  'html/app.js'
}

client_scripts {
  'client/main.lua'
}
