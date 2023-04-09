#!/usr/bin/env ruby

require "fileutils"
require "pathname"

include FileUtils::Verbose

$compile_deps = !$*.find_index("--no-deps")
$only_setup = $*.find_index("--setup-env")

arch = %x[arch].chomp
$homebrew_patch = if arch == "arm64"
                    "homebrew_arm.patch"
                  else
                    "homebrew_x86.patch"
                  end
$current_dir = "#{`pwd`.chomp}"
$homebrew_path = "#{`brew --repository`.chomp}/"

# system "brew tap iina/mpv-iina"

def install(package)
  system "brew reinstall #{package} --build-from-source"
end

def fetch(package)
  system "brew fetch -f -s #{package}"
end

def patch_luajit
  file_path = "#{`brew edit --print-path luajit`}".chomp
  lines = Pathname(file_path).readlines
  lines.filter! { |line| !line.end_with?("ENV[\"MACOSX_DEPLOYMENT_TARGET\"] = MacOS.version\n") }
  File.open(file_path, 'w') { |file| file.write lines.join }
end

def patch_rubberband
  file_path = "#{`brew edit --print-path rubberband`}".chomp
  lines = Pathname(file_path).readlines
  arg_line = lines.index { |l| l.end_width? "args = [\"-Dresampler=libsamplerate\"]\n" }
  lines.insert(arg_line + 1, "args << \"-Dcpp_args=-mmacosx-version-min=10.11\"\n")
  File.open(file_path, 'w') { |file| file.write lines.join }
end

def livecheck(package)
  splitted = `brew livecheck rubberband`.split(/:|==>/).map { |x| x.strip }
  splitted[1] == splitted[2]
end

def setup_rb(package)
  system "sd 'def install' 'def install\n\tENV[\"CFLAGS\"] = \"-mmacosx-version-min=10.11\"\n\tENV[\"LDFLAGS\"] = \"-mmacosx-version-min=10.11\"\n\tENV[\"CXXFLAGS\"] = \"-mmacosx-version-min=10.11\"\n' $(brew edit --print-path #{package})"
end

def setup_env
  system "brew update --auto-update"
  ENV["HOMEBREW_NO_AUTO_UPDATE"] = "1"
  ENV["HOMEBREW_NO_INSTALL_UPGRADE"] = "1"
  ENV["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
  ENV["HOMEBREW_NO_INSTALL_FROM_API"] = "1"
  FileUtils.cd $homebrew_path
  system "git reset --hard HEAD"
  print "Applying Homebrew patch (MACOSX_DEPLOYMENT_TARGET & oldest CPU)\n"
  system "git apply #{$current_dir}/#{$homebrew_patch}"
end

def reset
  return if $only_setup
  FileUtils.cd $homebrew_path
  system "git reset --hard HEAD"
end

begin
  setup_env
  return if $only_setup
  if arch != "arm64"
    pkgs = ["rubberband", "libpng", "luajit", "glib"]
    pkgs.each do |dep|
      setup_rb dep
    end
    print "#{pkgs} rb files prepared\n"
  end

  deps = "#{`brew deps mpv-iina -n`}".split("\n")
  total = deps.length + 1

  deps.each do |dep|
    fetch dep
  end
  fetch "mpv-iina"
  print "\n#{total} fetched\n"

  if $compile_deps
    print "#{total} packages to be compiled\n"

    deps.each do |dep|
      raise "brew livecheck failed for #{dep}" unless livecheck dep

      patch_luajit if dep.start_with?("luajit")
      patch_rubberband if dep.start_with?("rubberband")

      print "\nCompiling #{dep}\n"
      install dep
      total -= 1
      print "------------------------\n"
      print "#{dep} has been compiled\n"
      print "#{total} remained\n"
      print "------------------------\n"
    end
  end

  install "mpv-iina"

ensure
  reset
end
