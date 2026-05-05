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

require("lua/animations/animation")

-----------
--DISPLAY--
-----------

require("lua/display/monitors")
require("lua/display/rules")

------------
--PROGRAMS--
------------

require("lua/programs/autostart")
require("lua/programs/programs")

-------------
--VARIABLES--
-------------

require("lua/variables/environment")
require("lua/variables/misc")
require("lua/variables/permissions")

---------
--THEME--
---------

require("lua/theme/border")
require("lua/theme/theme")

---------
--INPUT--
---------

require("lua/input/input")
require("lua/input/keybinds")

-----------
--PLUGINS--
-----------

--require("lua/plugins/dynamic-cursors")

-----------
--HYPRMOD--
-----------

require("hyprmod")