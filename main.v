module main

import os
import term
import net.http
import time

fn is_sudo() ! {
	if !os.is_writable("/etc/") {
		return error(term.bright_red("Please run with sudo!"))
	}
}

// TODO: yes / no prompts
// TODO: show when dependencies are installed with a package
// TODO: spm publish request to spm repo server (make the server before tho)
fn main() {
	if (os.args.len == 2 && os.args[1] == "help") || os.args.len < 2 {
		println("spm help			show this")
		println("spm init			sets up spm")
		println("spm l				show all installed packages")
		println("spm i [package]		installs / updates the given package")
		println("spm fi [package]	force installs / updates the given package")
		println("spm r [package]		deletes the given package")
		println("spm u				list all updatable packages")
		println("spm u all			updates all updatable packages")
		println("spm fix				removes some corrupted packages")
		println("spm o				list working repos added to the remote file")
		println("spm f [name]		lists all packages containing [name]")
		println("spm d [package]		shows the description of a package")
		return
	}

	op := os.args[1]
	match op {
		"init" {
			is_sudo() or { return }
			if !os.is_dir("/etc/spm") {
				os.mkdir("/etc/spm")!
				os.mkdir("/etc/spm/pkgs")!
				os.mkdir("/etc/spm/pkgs/spm")!
				os.write_file("/etc/spm/pkgs/spm/pkg", "name<spm\nversion<3\nremote<http://207.180.202.42/files/spm-packages/spm\nfile</bin/spm\nfile</etc/spm\nrfile<install.sh\nrfile<spm")!
				os.write_file("/etc/spm/pkgs/pkcache", "spm=spm")!	// left: name in pkg		right: name in fs
				os.write_file("/etc/spm/repos", "http://207.180.202.42/files/spm-packages/\n")!
				println(term.bright_green("Done!"))
				println("It is recommended to run \"spm u all\" to update spm itself!")
				return
			}
			println(term.bright_yellow("Already initialised!"))
		}
		"o" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 2 {
				println(term.bright_red("Invalid arguments!"))
				return
			}

			a := os.read_lines("/etc/spm/repos")!
			mut working := 0
			for remote in a {
				mut stow := time.new_stopwatch(time.StopWatchOptions{auto_start: true})
				if http.get_text(remote + "/pkcache") != "" {
					ping := stow.elapsed()
					mut pingc := ping.str()
					if ping.milliseconds() < 40 {
						pingc = term.bright_green(pingc)
					}
					else if ping.milliseconds() < 80 {
						pingc = term.bright_yellow(pingc)
					}
					else {
						pingc = term.bright_red(pingc)
					}
					println("- $remote: ${term.bright_green("working")}: ping: $pingc")
					working ++
				} else {
					println("- $remote: ${term.bright_red("broken")}")
				}
				stow.stop()
			}
			if working == 0 {
				println(term.bright_red("No working repositories!"))
			}
			else {
				println(term.bright_green("$working working repositories!"))
			}
		}
		"l" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 2 {
				println(term.bright_red("Invalid arguments!"))
				return
			}
			broken, working := list_packages("/etc/spm/pkgs/")!
			for pk in working {
				println("- ${pk.name}: v${pk.version}")
			}
			if broken.len > 0 {
				println(term.bright_yellow("Package cache contains ${broken.len} corrupted / broken packages!\nPlease run \"spm fix\"!"))
			}
		}
		"i", "fi" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 3 {
				println(term.bright_red("Invalid arguments!"))
				return
			}

			install_package(os.args[2], "/etc/spm/pkgs/", 0, op == "fi", fn () {
				println(term.bright_red("Downgrading / reinstalling of packages is disabled!"))
			}, fn (from int, to int) {
				println(term.bright_green("Successfully updated ${os.args[2]} from v$from to v$to!"))
			}, fn (version int) {
				println(term.bright_green("Successfully installed ${os.args[2]} version $version!"))
			}, fn (lib string) {
				println(term.bright_red("Could not resolve library $lib!"))
			}, os.read_lines("/etc/spm/repos")!) or {
				println(err)
				return
			}
		}
		"r" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 3 {
				println(term.bright_red("Invalid arguments!"))
				return
			}
			if os.args[2] == "spm" {
				println(term.bright_red("Dont remove spm via \"spm r spm\"!\nUse \"spm self_uninstall\" instead!\n(Removing spm is not recommended!)"))
				return
			}
			is_sudo() or { return }

			path := get_pkg_path_from_cache(os.read_lines("/etc/spm/pkgs/pkcache")!, os.args[2]) or {
				println(term.bright_red("Package not found!"))
				return
			}
			remove_pkg(path) or {
				print(term.bright_red("Error removing package: "))
				println(err)
			}

			println(term.bright_yellow("Package removed!"))
		}
		"u" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len == 2 {
				a := updatable_pkgs_dirlist()
				for pkg in a {
					pk := get_pkg_from_path("/etc/spm/pkgs/${pkg.name}") or { continue }
					println("- " + pk.name)
				}
				if a.len == 0 {
					println(term.bright_green("All packages are up to date!"))
				}
				else {
					println(term.bright_yellow("${a.len} package(s) are updatable!"))
				}
			}
			else if os.args.len == 3 && os.args[2] == "all" {
				is_sudo() or { return }
				a := updatable_pkgs_dirlist()
				for pkg in a {
					pk := get_pkg_from_path("/etc/spm/pkgs/${pkg.name}") or { continue }
					println("Updating " + pk.name)
					download_package(pkg.remote) or {
						print(term.red("Error updating package ${pkg.name}: "))
						println(err)
						continue
					}
					println(term.bright_green("Updated ${pk.name}!"))
				}
				if a.len == 0 {
					println(term.bright_green("All packages are up-to-date!"))
				}
				else {
					println(term.bright_green("${a.len} package(s) have been updated!"))
				}
			}
			else {
				println(term.bright_red("Invalid arguments!"))
				return
			}
		}
		"fix" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 2 {
				println(term.bright_red("Invalid arguments!"))
				return
			}
			is_sudo() or { return }
			cache := os.read_lines("/etc/spm/pkgs/pkcache")!
			mut newcache := []string {}
			for cp in cache {
				a := cp.split("=")
				get_pkg_from_path("/etc/spm/pkgs/${a[1]}") or {
					println(term.bright_yellow("Removed corrupted package ${a[0]}"))
					continue
				}
				newcache << cp
			}
			os.write_file("/etc/spm/pkgs/pkcache", newcache.join("\n"))!
			println(term.bright_green("Done!"))
		}
		"self_uninstall" {
			if os.args.len != 3 || os.args[2] != "yes" {
				println(term.bright_red("To remove spm completely, run \"spm self_uninstall yes\"!"))
				return
			}
			is_sudo() or { return }
			os.rmdir_all("/etc/spm")!
			os.rm("/bin/spm")!
			println(term.bright_yellow("Uninstalled spm!"))
		}
		"f" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 3 {
				println(term.bright_red("Invalid arguments!"))
				return
			}

			mut ft := []string {}
			for remote in os.read_lines("/etc/spm/repos")! {
				a := http.get_text("$remote/pkcache")
				if a == "" {
					continue
				}
				for ci in a.split("\n") {
					if ci.len == 0 {
						continue
					}
					b := ci.split("=")
					if b[0].contains(os.args[2]) {
						ft << b[0]
					}
				}
			}

			if ft.len == 0 {
				println(term.bright_red("No package containing \"${os.args[2]}\" found!"))
				return
			}
			for f in ft {
				println("- $f")
			}
		}
		"d" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 3 {
				println(term.bright_red("Invalid arguments!"))
				return
			}
			pkr := find_package_in_remotes(os.read_lines("/etc/spm/repos")!, os.args[2]) or {
				println(term.bright_red("Package not found!"))
				return
			}
			t := http.get_text(pkr + "/pkg")
			if t == "" {
				println(term.bright_red("Remote package corrupted!"))
				return
			}
			pk := get_pkg_from_text(t.split_into_lines()) or {
				println(term.bright_red("Remote package corrupted!"))
				return
			}
			if pk.desc == "" {
				println(term.bright_yellow("Package has no description!"))
				return
			}
			println(pk.desc)
		}
		else {
			println(term.bright_red("Invalid arguments!"))
		}
	}
}
