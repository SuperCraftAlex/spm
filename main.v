module main

import os
import term
import net.http
import time

fn is_sudo() ! {
	if !os.is_writable("/etc/") {
		println(term.bright_red("Please run with sudo!"))
		return error(term.bright_red("Please run with sudo!"))
	}
}

// TODO: yes / no prompts
// TODO: show when dependencies are installed with a package
// TODO: spm publish request to spm repo server (make the server before tho)
// TODO: backup files before updating
fn main() {
	if (os.args.len == 2 && os.args[1] == "help") || os.args.len < 2 {
		println("spm help			show this")
		println("spm init			sets up spm")
		println("spm l				show all installed packages")
		println("spm i [package]			installs / updates the given package")
		println("spm fi [package]		force installs / updates the given package")
		println("spm r [package]			deletes the given package")
		println("spm u				list all updatable packages")
		println("spm u all			updates all updatable packages")
		println("spm fix				removes some corrupted packages")
		println("spm o				list working repos added to the remote file")
		println("spm f [name]			lists all packages containing [name]")
		println("spm d [package]			shows the description of a package")
		return
	}

	op := os.args[1]
	match op {
		"list" {
			if os.args[2] == "-i" {
				_, working := m_list_packages("/etc/spm/pkgs/")!
				for _ in working {
					println("THIS IS JUST IMPLEMENTED FOR NEOFETCH SUPPORT WITHOUT CHANGING NEOFETCH CODE! (\"tricks\" neofetch into spm beeing swift-package-manager)")
				}
			}
		}
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
			broken, working := m_list_packages("/etc/spm/pkgs/")!
			for pk in working {
				println("- ${pk.name}: " + term.gray("v${pk.version}"))
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

			for x in os.args[2].split(",") {
				f_install(x, op == "fi") or {
					println(err)
					return
				}
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

			for pk in os.args[2].split(",").map(fn (x string) string {return x.trim_space()}) {
				f_removepkg(pk) or {
					println(err)
				}
			}
		}
		"u" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len == 2 {
				f_list_updateable()
			}
			else if os.args.len == 3 {
				if os.args[2] == "all" {
					f_update(b_updateable_pkgs_list("/etc/spm/pkgs/", os.read_lines("/etc/spm/repos")!).tostring())!
				}
				else if os.args[2] == "fall" {
					f_update(m_list_packages_s("/etc/spm/pkgs/")!)!
				}
				else {
					f_update(os.args[2].split(",").map(fn (x string) string {return x.trim_space()}))!
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

			f_fix()!
		}
		"self_uninstall" {
			if os.args.len != 3 || os.args[2] != "yes" {
				println(term.bright_red("To remove spm completely, run \"") + term.yellow("spm self_uninstall yes") + term.bright_red("\"!"))
				return
			}
			f_self_uninstall()!
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

			f_find(os.args[2])!
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
			f_get_description(os.args[2])!
		}
		else {
			println(term.bright_red("Invalid arguments!"))
		}
	}
}
