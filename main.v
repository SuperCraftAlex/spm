module main

import os
import term
import net.http
import time

struct Package {
	name string
	version int

	files []string

	remote string
	remotfiles []string

	desc string
}

fn get_pkg_from_text(txt []string) !&Package {
	mut name := ""
	mut version := ""
	mut files := []string {}
	mut remote := "local"
	mut rfiles := []string {}
	mut desc := ""

	for l in txt {
		if l.trim_space().len == 0 {
			continue
		}
		a := l.split("<")
		if a.len != 2 {
			return error(term.bright_red("Corrupted pkg file!"))
		}
		match a[0] {
			"name" { name = a[1] }
			"version" { version = a[1] }
			"file" { files << a[1] }
			"remote" { remote = a[1] }
			"rfile" { rfiles << a[1] }
			"desc" { desc = a[1] }

			else {}
		}
	}

	v := version.int()
	if v == 0 {
		return error(term.bright_red("Invalid package version! Only ints > 0 allowed!"))
	}

	return &Package {
		name: name
		version: v
		files: files
		remote: remote
		remotfiles: rfiles
		desc: desc
	}
}

fn get_pkg_from_path(path string) !&Package {
	if !os.is_readable(path + "/pkg") {
		return error(term.bright_red("Not readable!"))
	}

	return get_pkg_from_text(os.read_lines(path + "/pkg")!)
}

fn get_pkg_path_from_cache(cache []string, pkg string) !string {
	for cp in cache {
		a := cp.split("=")
		if a[0] == pkg {
			return a[1]
		}
	}
	return error("Package not found!")
}

// find_package_in_remotes returns the url of the path to the package on any remote OR and error if it doesnt exist
fn find_package_in_remotes(remotes []string, pkg string) !string {
	for remote in remotes {
		a := http.get_text("$remote/pkcache")
		if a == "" {
			continue
		}
		for ci in a.split("\n") {
			if ci.len == 0 {
				continue
			}
			b := ci.split("=")
			if b[0] == pkg {
				return "$remote/${b[1]}"
			}
		}
	}
	return error("Package found nowhere!")
}

fn remove_pkg(dirname string) ! {
	if os.is_dir("/etc/spm/pkgs/$dirname") {
		pk := get_pkg_from_path("/etc/spm/pkgs/$dirname") or {
			os.rmdir_all("/etc/spm/pkgs/$dirname") or {
				return error(term.red("Cannot delete package directory!"))
			}
			return
		}
		if os.is_file("/etc/spm/pkgs/$dirname/uninstall.sh") {
			os.chmod("/etc/spm/pkgs/$dirname/uninstall.sh", 777) or {
				return error(term.red("Cannot make uninstall script executable!"))
			}
			os.chdir("/etc/spm/pkgs/$dirname/")!
			os.execute("bash /etc/spm/pkgs/$dirname/uninstall.sh")
		}
		os.rmdir_all("/etc/spm/pkgs/$dirname") or {
			return error(term.red("Cannot delete package directory!"))
		}
		if dirname != "spm" {
			for f in pk.files {
				if os.is_dir(f) {
					os.rmdir_all(f) or {}
				}
				if os.is_file(f) {
					os.rm(f) or {}
				}
			}
		}
	}

	cache := os.read_lines("/etc/spm/pkgs/pkcache") or { return }
	mut newcache := []string {}
	for cp in cache {
		a := cp.split("=")
		if dirname != a[1] {
			newcache << cp
		}
	}
	os.write_file("/etc/spm/pkgs/pkcache", newcache.join("\n")) or {}
}

fn download_package(remote string) ! {
	mut dirname := remote.all_after_last("/")
	if remote.ends_with("/") {
		dirname = remote#[..-1].all_after_last("/")
	}
	remove_pkg(dirname)!
	pkf := http.get_text(remote + "/pkg")
	pk := get_pkg_from_text(pkf.split_into_lines()) or {
		return error(term.bright_red("Remote url not a package!"))
	}
	os.mkdir("/etc/spm/pkgs/$dirname/") or {
		return error(term.bright_red("Error creating dir for pkg!"))
	}
	os.write_file("/etc/spm/pkgs/$dirname/pkg", pkf) or {
		return error(term.bright_red("No permissions to install package!"))
	}
	for rfile in pk.remotfiles {
		os.write_file("/etc/spm/pkgs/$dirname/$rfile", http.get_text(remote + "/$rfile")) or {}
	}

	mut cache := os.read_lines("/etc/spm/pkgs/pkcache") or {
		return error(term.bright_red("Package cache broken!"))
	}
	cache << pk.name + "=" + dirname
	os.write_file("/etc/spm/pkgs/pkcache", cache.join("\n")) or {
		return error(term.bright_red("No permissions to install package!"))
	}

	if os.is_file("/etc/spm/pkgs/$dirname/install.sh") {
		os.chmod("/etc/spm/pkgs/$dirname/install.sh", 777) or {
			return error(term.red("Cannot make install script executable!"))
		}
		os.chdir("/etc/spm/pkgs/$dirname/")!
		os.execute("bash /etc/spm/pkgs/$dirname/install.sh")
	}
}

fn updatable_pkgs_dirlist() []&Package {
	mut upa := []&Package {}

	for pkgf in os.read_lines("/etc/spm/pkgs/pkcache") or { return upa } {
		pkg := pkgf.all_after_first("=").trim_space()
		if !os.is_file("/etc/spm/pkgs/$pkg/pkg") {
			continue
		}
		pk := get_pkg_from_path("/etc/spm/pkgs/$pkg") or { continue }

		if pk.remote != "local" {
			remotetxt := http.get_text(pk.remote + "/pkg")
			if remotetxt != "" {
				rpk := get_pkg_from_text(remotetxt.split_into_lines()) or { continue }
				if rpk.version > pk.version {
					upa << &Package {
						name: pkgf.before("=").trim_space()		// not real name! (is directory name)
						remote: pk.remote
					}
				}
				continue
			}
		}
		pa := find_package_in_remotes(os.read_lines("/etc/spm/repos") or { return upa } , pkg) or { continue }
		remotetxt := http.get_text(pa + "/pkg")
		if remotetxt != "" {
			rpk := get_pkg_from_text(remotetxt.split_into_lines()) or { continue }
			if rpk.version > pk.version {
				upa << &Package {
					name: pkgf.before("=").trim_space()			// not real name! (is directory name)
					remote: pa
				}
			}
			continue
		}
	}

	return upa
}

fn main() {
	if (os.args.len == 2 && os.args[1] == "help") || os.args.len < 2 {
		println("spm help			show this")
		println("spm init			sets up spm")
		println("spm l				show all installed packages")
		println("spm i [package]		installs / updates the given package")
		println("spm r [package]		deletes the given package")
		println("spm u				list all updatable packages")
		println("spm u all			updates all updatable packages")
		println("spm fix				removes some corrupted packages")
		println("spm o				list working repos added to the remote file")
		println("spm f [name]		lists all packages containing [name]")
		println("spm d [package]		shows the description of a package")
		return
	}

	if !os.is_writable("/etc/") {
		println(term.bright_red("Please run with sudo!"))
		return
	}

	op := os.args[1]
	match op {
		"init" {
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
			mut has_broken_pkgs := false
			for pkgf in os.read_lines("/etc/spm/pkgs/pkcache")! {
				pkg := pkgf.all_after_first("=").trim_space()
				if !os.is_file("/etc/spm/pkgs/$pkg/pkg") {
					has_broken_pkgs = true
					continue
				}
				pk := get_pkg_from_path("/etc/spm/pkgs/$pkg") or {
					println(err)
					return
				}
				println("- ${pk.name}: v${pk.version}")
			}
			if has_broken_pkgs {
				println(term.bright_yellow("Package cache contains packages that dont exist here anymore!\nPlease run \"spm fix\"!"))
			}
		}
		"i" {
			if !os.is_dir("/etc/spm") {
				println(term.bright_red("Please run \"spm init\" first!"))
				return
			}
			if os.args.len != 3 {
				println(term.bright_red("Invalid arguments!"))
				return
			}
			pkp := get_pkg_path_from_cache(os.read_lines("/etc/spm/pkgs/pkcache")!, os.args[2]) or {
				pkp := find_package_in_remotes(os.read_lines("/etc/spm/repos")!, os.args[2]) or {
					println(term.bright_red("Package not found in any repository in the local repo list (\"/etc/spm/repos\")!"))
					return
				}
				download_package(pkp) or {
					print(term.bright_red("Error downloading package: "))
					println(err)
					return
				}
				println(term.bright_green("Installed package!"))
				return
			}

			// update package
			pk := get_pkg_from_path("/etc/spm/pkgs/" + pkp) or {
				println(err)
				return
			}

			rtxt := http.get_text(pk.remote+"/pkg")

			if pk.remote == "local" || rtxt == "" {
				if rtxt == "" && pk.remote != "local" {
					println(term.bright_yellow("Specified remote url from package returns empty response!\nSearching in all repositories..."))
				}
				pkpp := find_package_in_remotes(os.read_lines("/etc/spm/repos")!, os.args[2]) or {
					println(term.bright_red("Package not found in any repository in the local repo list (\"/etc/spm/repos\")!"))
					return
				}
				wblc := http.get_text(pkpp + "/pkg")
				if wblc == "" {
					println(term.bright_red("Broken repository entry!"))
					return
				}
				pktxt := get_pkg_from_text(wblc.split_into_lines()) or {
					println(term.bright_red("Remote package corrupted!"))
					return
				}
				if pktxt.version <= pk.version {
					println(term.bright_yellow("Remote package version lower or equal than current version. Installing anyway."))
				}
				download_package(pkpp) or {
					print(term.bright_red("Error downloading package: "))
					println(err)
					return
				}
				println(term.bright_green("Updated package!"))
				return
			}

			pktxt := get_pkg_from_text(rtxt.split_into_lines()) or {
				println(term.bright_red("Remote package corrupted!"))
				return
			}

			if pktxt.version <= pk.version {
				println(term.bright_yellow("Remote package version lower or equal than current version. Installing anyway."))
			}

			download_package(pk.remote) or {
				print(term.bright_red("Error downloading package: "))
				println(err)
				return
			}

			println(term.bright_green("Updated package!"))
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
				a := updatable_pkgs_dirlist()
				for pkg in a {
					pk := get_pkg_from_path("/etc/spm/pkgs/${pkg.name}") or { continue }
					println("Updating " + pk.name)
					download_package(pkg.remote) or {
						print(term.red("Error updating package ${pkg.name}: "))
						println(err)
					}
				}
				if a.len == 0 {
					println(term.bright_green("All packages are up to date!"))
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
