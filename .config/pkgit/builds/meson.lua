return {
  targets = {
    default = {
      build = function()
        return os.execute("meson setup build --prefix "..prefix.." && meson compile -C build")
      end,
      install = function()
        return os.execute("cd build && meson install")
      end,
      uninstall = function()
        return os.execute("cd build && ninja uninstall")
      end
    },
    quiet = {
      build = function()
        return os.execute("meson setup build --prefix "..prefix.." &>/tmp/pkgit_build.log && meson compile -C build &>/tmp/pkgit_build.log")
      end,
      install = function()
        return os.execute("cd build && meson install &>/tmp/pkgit_build.log")
      end,
      uninstall = function()
        return os.execute("cd build && ninja uninstall &>/tmp/pkgit_build.log")
      end
    }
  }
}
