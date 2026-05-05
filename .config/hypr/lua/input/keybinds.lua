-- Set "Windows" key as main modifier --
local MOD = "SUPER"

-- Functions --
local function forceKillActive()
    local w = hl.get_active_window()
    if w ~= nil then
        os.execute("kill -9 " .. w.pid)
    end
end

local function toggle_brightness(display, values)
    local handle = io.popen("ddcutil getvcp 10 --display " .. display)
    local output = handle:read("*a")
    handle:close()

    local current = tonumber(output:match("current value%s*=%s*(%d+)"))

    if current ~= nil then
        for i, v in ipairs(values) do
            if v == current then
                local next_val = values[i + 1] or values[1]
                os.execute("ddcutil setvcp 10 " .. next_val .. " --display " .. display)
                return
            end
        end
    end

    os.execute("ddcutil setvcp 10 " .. values[1] .. " --display " .. display)
end

local function toggle_power(display)
    local state_file = "/tmp/monitor_" .. display .. "_power_state"
    local power_off_code = (display == 2) and "0x04" or "0x02"

    local f = io.open(state_file, "r")
    if f then
        f:close()
        os.execute("ddcutil setvcp d6 0x01 --display " .. display .. " --sleep-multiplier 0.1")
        os.remove(state_file)
    else
        os.execute("ddcutil setvcp d6 " .. power_off_code .. " --display " .. display .. " --sleep-multiplier 0.1")
        io.open(state_file, "w"):close()
    end
end

local function toggle_shell()
    local function is_running(process)
        local handle = io.popen("pgrep -x " .. process)
        local result = handle:read("*a")
        handle:close()
        return result ~= ""
    end

    if is_running("qs") or is_running("linux-wallpaperengine") then
        os.execute("killall -9 qs")
        os.execute("killall -9 linux-wallpaperengine")
    else
        os.execute("linux-wallpaperengine --silent --screen-root DP-1 --bg 2638946149 &")
        os.execute("linux-wallpaperengine --silent --disable-mouse --disable-parallax --set-property timeofday=3 --screen-root HDMI-A-1 --bg 2504353624 &")
        os.execute("qs -c noctalia-shell &")
    end
end

-- App Control --
hl.bind(MOD .. " + S", hl.dsp.exec_cmd(music))
hl.bind(MOD .. " + D", hl.dsp.exec_cmd(discord))
hl.bind(MOD .. " + C", hl.dsp.exec_cmd(code))
hl.bind(MOD .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(MOD .. " + W", function() toggle_shell() end)
hl.bind(MOD .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(MOD .. " + M", hl.dsp.exec_cmd(mail))
hl.bind(MOD .. " + O", hl.dsp.exec_cmd(notes))
hl.bind(MOD .. " + SHIFT + B", hl.dsp.exec_cmd(privateBrowser))
hl.bind(MOD .. " + Super_L", hl.dsp.exec_cmd(menu))
hl.bind(MOD .. " + SPACE", hl.dsp.exec_cmd(noctalia .. " controlCenter toggle"))
hl.bind(MOD .. " + comma", hl.dsp.exec_cmd(noctalia .. " settings toggle"))
hl.bind(MOD .. " + period", hl.dsp.exec_cmd("emote"))
hl.bind(MOD .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(MOD .. " + SHIFT + RETURN", hl.dsp.exec_cmd(terminal_float))

-- Media Control --
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctalia .. " volume increase"), { repeating = true, locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctalia .. " volume decrease"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(noctalia .. " volume muteOutput"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(noctalia .. " brightness increase"), { repeating = true, locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctalia .. " brightness decrease"), { repeating = true, locked = true })

-- Screenshot Tools --
hl.bind(MOD .. " + SHIFT + S", hl.dsp.exec_cmd(hyprcap))
hl.bind("PRINT", hl.dsp.exec_cmd(screenshot))

-- Lockscreen Control --
hl.bind(MOD .. " + SHIFT + L", hl.dsp.exec_cmd(noctalia .. " lockScreen lock"))

-- Monitor Control --
hl.bind("CTRL + F1", function() toggle_brightness(2, {0, 80}) end)
hl.bind("CTRL + F2", function() toggle_power(2) end)
hl.bind("CTRL + F3", function() toggle_brightness(1, {0, 50, 100}) end)
hl.bind("CTRL + F4", function() toggle_power(1) end)

-- Workspace Control
hl.bind(MOD .. " + mouse_down", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(MOD .. " + mouse_up", hl.dsp.focus({ workspace = "m+1" }))
for i = 1, 9 do
    hl.bind(MOD .. " + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
end
hl.bind(MOD .. " + 0", hl.dsp.focus({ workspace = "10" }))

-- Window Control --
hl.bind("F11", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(MOD .. " + F", hl.dsp.window.fullscreen({ mode = 1 }))
hl.bind(MOD .. " + Q", hl.dsp.window.close())
hl.bind(MOD .. " + SHIFT + Q", function() forceKillActive() end)
hl.bind(MOD .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(MOD .. " + SHIFT + C", hl.dsp.window.center())
hl.bind(MOD .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(MOD .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- System Control --
hl.bind(MOD .. " + ESCAPE", hl.dsp.exec_cmd("nwg-bar"))