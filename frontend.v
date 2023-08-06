module main

import term
import os
import net.http

fn f_removepkg(pkname string)! {
	is_sudo() or { return error(term.bright_red("Not sudo!")) }

	if pkname == "spm" {
		return error(term.bright_red("Dont remove spm via \"spm r spm\"!\nUse \"") + term.yellow("spm self_uninstall") + term.bright_red("\" instead!\n(Removing spm is not recommended!)"))
	}

	path := b_get_pkg_path_from_cache(os.read_lines("/etc/spm/pkgs/pkcache")!, pkname) or {
		return error(term.bright_red("Package not found: $pkname!"))
	}

	pk := b_get_pkg_from_path("/etc/spm/pkgs/" + path) or {
		return error(term.bright_red("Corrupted package: $pkname!"))
	}

	_, working := m_list_packages("/etc/spm/pkgs/")!
	mut breaks := []string {}
	for p in working {
		if p.dependencies.contains(pk.name) {
			breaks << p.name
		}
	}
	if breaks.len > 0 {
		println(term.bright_red("Removing package ${pk.name} breaks dependency with ${breaks.len} packages:"))
		for b in breaks {
			println(term.bright_red("- $b"))
		}
		return error(term.bright_red("Removing package ${pk.name} breaks dependency with ${breaks.len} packages!"))
	}

	b_remove_pkg(path, "/etc/spm/pkgs/") or {
		return error(term.bright_red("Error removing package $pkname: ${err.msg()}"))
	}

	println(term.bright_yellow("Package $pkname removed!"))
}

fn f_list_updateable() {
	a := b_updateable_pkgs_list("/etc/spm/pkgs/", os.read_lines("/etc/spm/repos") or {[""]})
	for pkg in a {
		pk := b_get_pkg_from_path("/etc/spm/pkgs/${pkg.name}") or { continue }
		println("- " + pk.name)
	}
	if a.len == 0 {
		println(term.bright_green("All packages are up to date!"))
	}
	else {
		println(term.bright_yellow("${a.len} package(s) are updatable!"))
	}
}

fn f_update(pkgs []string)! {
	is_sudo() or { return }

	a := m_get_packages("/etc/spm/pkgs/", pkgs) or {
		println(term.bright_red("Package(s) not found!"))
		return
	}
	for pk in a {
		println("Updating ${pk.name}...")
		m_install_package(pk.name, "/etc/spm/pkgs/", 0, false, fn () {},
			fn(pack string, from int, to int) {
				println(term.bright_green("Updated $pack from v$from to v$to!"))
			}, fn(pack string, version int) {
				println(term.bright_green("- installed $pack=$version!"))
			}, fn(lib string) {
				println(term.bright_red("- error installing required library $lib!"))
			}, os.read_lines("/etc/spm/repos") or { return err }
		) or {
			println(term.bright_red("Error updating package ${pk.name}!"))
		}
	}
	if a.len == 0 {
		println(term.bright_green("All packages are up-to-date!"))
	}
	else {
		println(term.bright_green("${a.len} package(s) have been updated!"))
	}
}

fn f_fix()! {
	is_sudo() or { return }
	cache := os.read_lines("/etc/spm/pkgs/pkcache")!
	mut newcache := []string {}
	for cp in cache {
		a := cp.split("=")
		b_get_pkg_from_path("/etc/spm/pkgs/${a[1]}") or {
			println(term.bright_yellow("Removed corrupted package ${a[0]}"))
			continue
		}
		newcache << cp
	}
	os.write_file("/etc/spm/pkgs/pkcache", newcache.join("\n"))!
	println(term.bright_green("Done!"))
}

fn f_install(pkg string, force bool)! {
	is_sudo() or { return error(term.bright_red("Not sudo!")) }

	mut errs := 0
	m_install_package(pkg, "/etc/spm/pkgs/", 0, force, fn [mut errs]() {
		println(term.bright_red("Downgrading / reinstalling of packages is disabled!"))
		errs ++
	}, fn [mut errs](pk string, from int, to int) {
		println(term.bright_green("Updated $pk from v$from to v$to!"))
		errs ++
	}, fn [mut errs](pk string, version int) {
		println(term.bright_green("Installed $pk version $version!"))
		errs ++
	}, fn [mut errs](lib string) {
		println(term.bright_red("Could not resolve library $lib!"))
		errs ++
	}, os.read_lines("/etc/spm/repos")!) or {
		return err
	}

	if errs > 0 {
		return error("Error occured!")
	}
}

fn f_self_uninstall()! {
	is_sudo() or { return }
	os.rmdir_all("/etc/spm")!
	os.rm("/bin/spm")!
	println(term.bright_yellow("Uninstalled spm!"))
}

fn f_find(txt string)! {
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
			if b[0].contains(txt) {
				ft << b[0]
			}
		}
	}

	if ft.len == 0 {
		println(term.bright_red("No package containing \"$txt\" found!"))
		return
	}
	for f in ft {
		println("- $f")
	}
}

fn f_get_description(name string)! {
	pkr := b_find_package_in_remotes(os.read_lines("/etc/spm/repos")!, name) or {
		println(term.bright_red("Package not found!"))
		return
	}
	t := http.get_text(pkr + "/pkg")
	if t == "" {
		println(term.bright_red("Remote package corrupted!"))
		return
	}
	pk := b_get_pkg_from_text(t.split_into_lines()) or {
		println(term.bright_red("Remote package corrupted!"))
		return
	}
	if pk.desc == "" {
		println(term.bright_yellow("Package has no description!"))
		return
	}
	println(pk.desc)
}