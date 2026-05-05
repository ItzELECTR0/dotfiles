-- Program Permissions
hl.permission({
    binary = "/usr/(bin|local/bin)/grim",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(bin|local/bin)/wf-recorder",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(bin|local/bin)/hyprcap",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(bin|local/bin)/hyprpicker",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(bin|local/bin)/pipewire",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(bin|local/bin)/pipewire-pulse",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
    type = "screencopy",
    mode = "allow"
})
hl.permission({
    binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal",
    type = "screencopy",
    mode = "allow"
})

-- Device Permissions
hl.permission({
    binary = "gsr-ui-virtual-keyboard",
    type = "keyboard",
    mode = "allow"
})
hl.permission({
    binary = "logitech-pro-gaming-keyboard",
    type = "keyboard",
    mode = "allow"
})
hl.permission({
    binary = ".*",
    type = "keyboard",
    mode = "deny"
})