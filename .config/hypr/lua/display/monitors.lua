hl.monitor({
    output = "DP-1",
    mode = "2560x1440@170.00",
    scale = 1
    position = "0x0"
    transform = 0
    bitdepth = 10
    cm = "srgb"
    ---sdrbrightness = 1.00
    ---sdrsaturation = 1.10
    ---sdr_min_luminance = 0.1
    ---sdr_max_luminance = 100
    vrr = 0
})

hl.monitor({
    output = HDMI-A-1
    mode = 1920x1080@75.00
    scale = 1
    position = -1080x-385
    transform = 1
    bitdepth = 8
    cm = "srgb"
    vrr = 0
})

hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1
})