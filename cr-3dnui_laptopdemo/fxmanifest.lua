fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Cody / CR-3DNUI'
description 'CR-3DNUI Laptop ReplaceTexture Demo'
version '1.0.0'

client_scripts {
  'client.lua'
}

-- Keep the UI page as the invisible input bridge (it does not need to be visible).
ui_page 'html/input.html'

-- IMPORTANT: DUI pages MUST be listed here or FiveM will 404 them (black texture).
files {
  'html/*.html',
  'html/*.css',
  'html/*.js'
}
