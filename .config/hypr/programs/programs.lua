noctaliaBin       = "noctalia"
noctalia          = noctaliaBin .. " msg"
nocLauncher       = noctalia .. " panel-toggle launcher"
nocControlCenter  = noctalia .. " panel-toggle control-center"
nocSessionMenu    = noctalia .. " panel-toggle session"
nocSettings       = noctalia .. " settings-toggle"
nocVolumeUp       = noctalia .. " volume-up 5"
nocVolumeDown     = noctalia .. " volume-down 5"
nocVolumeMute     = noctalia .. " volume-mute"
nocBrightnessUp   = noctalia .. " brightness-up 5"
nocBrightnessDown = noctalia .. " brightness-down 5"
nocLock           = noctalia .. " session lock"
nocWindowSwitcher = noctalia .. " window-switcher"
nocTailscale      = noctalia .. " panel-toggle davemhammer/tailscale:manager"

function discord()
    local variants = {
        { cmd = "discord-canary", proc = "DiscordCanary", label = "Discord Canary" },
        { cmd = "discord-ptb",    proc = "DiscordPTB",    label = "Discord PTB"    },
        { cmd = "discord",        proc = "Discord",       label = "Discord"        },
    }

    local wayland_flags = "--enable-features=UseOzonePlatform --ozone-platform=wayland"
 
    local function is_installed(bin)
        local h   = io.popen("command -v " .. bin .. " 2>/dev/null")
        local out = h:read("*l")
        h:close()
        return out ~= nil and out ~= ""
    end
 
    local function is_running(proc)
        local h   = io.popen("pgrep -x " .. proc .. " 2>/dev/null")
        local out = h:read("*l")
        h:close()
        return out ~= nil and out ~= ""
    end
 
    for _, v in ipairs(variants) do
        if is_installed(v.cmd) then
            hl.exec_cmd(v.cmd .. " " .. wayland_flags)
            return
        end
    end

    if #installed == 0 then
        hl.notification.create({
            text    = "Discord: no installation found.\nInstall discord, discord-ptb, or discord-canary from the AUR.",
            timeout = 5000,
            icon    = "dialog-error",
        })
    end
end

-- Set programs --
music = "feishin"
terminal = "kitty"
terminal_float = "kitty --class kitty-floating"
browser = "zen-browser-twilight"
alternateBrowser = "helium-browser"
privateBrowser = browser.." --private-window"
code = "vscodium-insiders"
fileManager = "thunar"
mail = "thunderbird"
notes = "obsidian"
sysmon = "cosmic-monitor"
sysinfo = "hyprsysteminfo"

-- Set commands --
menu = nocLauncher
hyprcap = dirs.scripts .. "/hyprcap.sh"
screenshot = "hyprcap shot monitor:active --copy"