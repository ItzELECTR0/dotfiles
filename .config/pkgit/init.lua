local home = os.getenv("HOME")
prefix = home.."/.local"

install_directories = {
  bin	    = prefix.."/bin",         -- binaries (executables)
  include	= prefix.."/include",     -- C headers
  lib	    = prefix.."/lib",         -- libraries (shared objects)
  src       = prefix.."/share/pkgit"  -- source code
}

repositories = require("repos.init")
build_systems = require("builds.init")
