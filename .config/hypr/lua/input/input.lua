hl.config({
    input = {
        kb_layout = "us,ro",
        kb_variant = ",std",
        kb_options = "grp:alt_shift_toggle",
        follow_mouse = 1,
        sensitivity = -0.8,
        accel_profile = "adaptive",
        scroll_factor = 1.0,
        left_handed = false,
        natural_scroll = false,
        touchpad = {
            tap_to_click = true
        }
    },

    cursor = {
        enable_hyprcursor = true,
        no_warps = true,
        persistent_warps = true,
        no_hardware_cursors = 0
    }
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})