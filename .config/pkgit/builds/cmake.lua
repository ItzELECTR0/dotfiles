return {
  targets = {
    default = {
      build = function()
        return os.execute("cmake -B build && cmake --build build")
      end,
      install = function()
        return os.execute("cmake --build . --target install")
      end,
      uninstall = function()
        return os.execute("xargs rm < install_manifest.txt")
      end,
    },
    quiet = {
      build = function()
        return os.execute("cmake -B build &>/tmp/pkgit_build.log && cmake --build build &>/tmp/pkgit_build.log")
      end,
      install = function()
        return os.execute("cmake --build . --target install &>/tmp/pkgit_build.log")
      end,
      uninstall = function()
        return os.execute("xargs rm < install_manifest.txt &>/tmp/pkgit_build.log")
      end,
    },
  }
}
