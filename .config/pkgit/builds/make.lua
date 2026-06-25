return {
  targets = {
    default = {
      build = function()
        return os.execute("make")
      end,
      install = function()
        return os.execute("make install PREFIX="..prefix)
      end,
      uninstall = function()
        return os.execute("make uninstall PREFIX="..prefix)
      end
    },
    quiet = {
      build = function()
        return os.execute("make &>/tmp/pkgit_build.log")
      end,
      install = function()
        return os.execute("make install PREFIX="..prefix.." &>/tmp/pkgit_build.log")
      end,
      uninstall = function()
        return os.execute("make uninstall PREFIX="..prefix.." &>/tmp/pkgit_build.log")
      end
    }
  }
}
