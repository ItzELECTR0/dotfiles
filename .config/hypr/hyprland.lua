-- ~/.config/hypr/hyprland.lua

---------------
--DIRECTORIES--
---------------

local home = os.getenv("HOME")
dirs = {
    home = home,
    dotfiles = home .. "/.dotfiles",
    scripts = home .. "/.dotfiles/scripts",
    desktop = home .. "/.dotfiles/scripts/desktop",
    config = home .. "/.config/hypr",
}

--------------
--ANIMATIONS--
--------------

require("animations/animation")

-----------
--DISPLAY--
-----------

require("display/monitors")
require("display/layouts")
require("display/rules")

------------
--PROGRAMS--
------------

require("programs/autostart")
require("programs/programs")

-------------
--VARIABLES--
-------------

require("variables/environment")
require("variables/misc")
require("variables/permissions")

---------
--THEME--
---------

require("theme/border")
require("theme/theme")

---------
--INPUT--
---------

require("input/input")
require("input/keybinds")

-----------
--PLUGINS--
-----------

--require("plugins/dynamic-cursors")

-----------
--HYPRMOD--
-----------

require("hyprmod")