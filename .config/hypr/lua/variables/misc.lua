hl.config({
    misc = {
        font_family = "Redwing",
        allow_session_lock_restore = true,
        animate_manual_resizes = true,
        animate_mouse_windowdragging = true,
        enable_swallow = true,
        swallow_regex = "^(kitty)$",
        disable_hyprland_logo = true,
        disable_splash_rendering = false,
        force_default_wallpaper = 0,
        middle_click_paste = true,
        disable_watchdog_warning = false,
        vrr = 0
    },

    opengl = {
        nvidia_anti_flicker = true
    },

    quirks = {
        prefer_hdr = 2
    },

    xwayland = {
        enabled = true,
        use_nearest_neighbor = true,
        force_zero_scaling = true,
        create_abstract_socket = true
    },

    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
        enforce_permissions = true
    }
})