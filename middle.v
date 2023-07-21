module main

import os
import net.http
import term

// list_packages lists all packages in the specified
fn list_packages(path string) !([]string, []&Package) {
	mut broken_pkgs := []string {}
	mut working_pkgs := []&Package {}

	for pkgf in os.read_lines("$path/pkcache")! {
		pkg := pkgf.all_before("=").trim_space()
		if !os.is_file("$path/$pkg/pkg") {
			broken_pkgs << pkg
			continue
		}
		pk := get_pkg_from_path("$path/$pkg") or {
			broken_pkgs << pkg
			continue
		}

		working_pkgs << pk
	}

	return broken_pkgs, working_pkgs
}

fn get_installed_package(name string, path string) !&Package {
	p := get_pkg_path_from_cache(os.read_lines(path + "/pkcache")!, name)!
	return get_pkg_from_path(path + "/" + p)
}

// install_package installs / updates the given package
//
// modes
//
//   0		install or update
//
//   1      update
fn install_package(name string, localpath string, mode int, update_if_dg bool, ifnot fn(), update_succes fn(from int, to int), install_succes fn(version int), error_library fn(lib string), repos []string) ! {
	is_sudo()!

	pk := get_installed_package(name, localpath) or {
		if mode == 1 {
			return error(term.bright_red("Package not installed!"))
		}

		p := find_package_in_remotes(repos, name)!
		npk := download_package(p)!

		mut errl := 0
		for dep in npk.dependencies {
			install_package(dep, localpath, 0, true, fn () {}, fn(a int, b int) {}, fn(a int) {}, fn [error_library](lib string) {error_library(lib)}, repos) or {
				error_library(dep)
				errl ++
			}
		}
		if errl > 0 {
			remove_pkg(p.all_after_last("/")) or {}
			return error(term.bright_red("Could not install $errl dependenc(ies)!"))
		}

		install_succes(npk.version)
		return
	}

	p := find_package_in_remotes(repos, name)!

	pkf := get_pkg_from_text(http.get_text(p + "/pkg").split_into_lines())!
	if !update_if_dg && pk.version >= pkf.version {
		ifnot()
		return
	}

	npk := download_package(p)!

	mut errl := 0
	for dep in npk.dependencies {
		install_package(dep, localpath, 0, true, fn () {}, fn(a  int, b int) {}, fn(a int) {}, fn [error_library](lib string) {error_library(lib)}, repos) or {
			error_library(dep)
			errl ++
		}
	}
	if errl > 0 {
		remove_pkg(p.all_after_last("/")) or {}
		return error(term.bright_red("Could not install $errl dependenc(ies)!"))
	}

	update_succes(pk.version, npk.version)
}