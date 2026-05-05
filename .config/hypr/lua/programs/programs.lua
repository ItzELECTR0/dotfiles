-- Set Noctalia shell call --
noctalia = "qs -c noctalia-shell ipc call"

-- Set programs
music = "feishin"
terminal = "kitty"
terminal_float = "kitty --class kitty-floating"
browser = "librewolf"
privateBrowser = "librewolf --private-window"
discord = dirs.scripts .. "/discord.sh"
code = "vscodium-insiders"
fileManager = "thunar"
mail = "thunderbird"
notes = "obsidian"

-- Set commands --
menu = noctalia .. " launcher toggle"
hyprcap = dirs.scripts .. "/hyprcap.sh"
screenshot = "hyprcap shot monitor:active --copy"