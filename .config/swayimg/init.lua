-- swayimg >= 5.0 config with parity to legacy ~/.config/swayimg/config

-- [general]
swayimg.set_mode("viewer")
swayimg.enable_decoration(false)
swayimg.enable_antialiasing(false)

-- [viewer]
swayimg.viewer.set_window_background(0xff000000)
swayimg.viewer.set_default_scale("fit")
swayimg.viewer.limit_preload(10)

-- [list]
swayimg.imagelist.enable_adjacent(true)
swayimg.imagelist.enable_recursive(false)
swayimg.imagelist.set_order("alpha")
swayimg.viewer.enable_loop(true)
swayimg.slideshow.enable_loop(true)

-- [info]
swayimg.text.set_foreground(0x00000000)
swayimg.text.set_background(0x00000000)
swayimg.text.set_shadow(0x00000000)
swayimg.viewer.set_text("topleft", {})
swayimg.viewer.set_text("topright", {})
swayimg.viewer.set_text("bottomleft", {})
swayimg.viewer.set_text("bottomright", {})
local function force_fit_scale()
  local mode = swayimg.get_mode()
  if mode == "viewer" then
    pcall(function()
      swayimg.viewer.set_fix_scale("fit")
    end)
  elseif mode == "slideshow" then
    pcall(function()
      swayimg.slideshow.set_fix_scale("fit")
    end)
  end
end
swayimg.on_initialized(function()
  force_fit_scale()
  swayimg.text.hide()
end)
swayimg.viewer.on_image_change(force_fit_scale)
swayimg.slideshow.on_image_change(force_fit_scale)

-- [keys.viewer]
swayimg.viewer.bind_reset()

swayimg.viewer.on_key("Left", function()
  swayimg.viewer.switch_image("prev")
end)

swayimg.viewer.on_key("Right", function()
  swayimg.viewer.switch_image("next")
end)

local function zoom(delta)
  local next_scale = swayimg.viewer.get_scale() + delta
  if next_scale < 0.01 then
    next_scale = 0.01
  end
  local mouse = swayimg.get_mouse_pos()
  swayimg.viewer.set_abs_scale(next_scale, mouse.x, mouse.y)
end

local function bind_scroll(scroll_name, fn)
  local ok = pcall(swayimg.viewer.on_mouse, scroll_name, fn)
  if not ok then
    swayimg.viewer.on_key(scroll_name, fn)
  end
end

bind_scroll("ScrollUp", function()
  zoom(0.10) -- legacy zoom +10
end)

bind_scroll("ScrollDown", function()
  zoom(-0.10) -- legacy zoom -10
end)

swayimg.viewer.on_key("r", function()
  swayimg.viewer.set_fix_scale("fit")
end)

swayimg.viewer.on_key("f", function()
  if swayimg.toggle_fullscreen then
    swayimg.toggle_fullscreen()
  else
    swayimg.set_fullscreen()
  end
end)

swayimg.viewer.on_key("q", function()
  swayimg.exit()
end)

swayimg.viewer.on_key("Escape", function()
  swayimg.exit()
end)
