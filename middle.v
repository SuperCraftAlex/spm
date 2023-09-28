module main

import os
import net.http
import term

fn m_list_packages_s(path string) ![]string {
	return os.read_lines('${path}/pkcache')!.map(fn (x string) string {
		return x.all_before('=')
	})
}

// m_list_packages lists all packages in the specified path (local) (has to contain pkcache file)
fn m_list_packages(path string) !([]string, []&Package) {
	mut broken_pkgs := []string{}
	mut working_pkgs := []&Package{}

	for mut pkgf in os.read_lines('${path}/pkcache')! {
		unsafe {
			all_before_first_modify_fast(pkgf.str, c'=')
			before_ctrl_codes_modify(pkgf.str)
			pkgf.len = vstrlen(pkgf.str)
		}
		if !os.is_file('${path}/${pkgf}/pkg') {
			broken_pkgs << pkgf
			continue
		}
		pk := b_get_pkg_from_path('${path}/${pkgf}') or {
			broken_pkgs << pkgf
			continue
		}

		working_pkgs << pk
	}

	return broken_pkgs, working_pkgs
}

fn m_get_installed_package(name string, path string) !&Package {
	p := b_get_pkg_path_from_cache(os.read_lines(path + '/pkcache')!, name)!
	return b_get_pkg_from_path(path + '/' + p)
}

// m_install_package installs / updates the given package
//
// modes
//
//   0		install or update
//   1      update
fn m_install_package(name string, localpath string, mode int, update_if_dg bool, ifnot fn (), update_succes fn (pack string, from int, to int), install_succes fn (pack string, version int), error_library fn (lib string), repos []string) ! {
	is_sudo()!

	pk := m_get_installed_package(name, localpath) or {
		if mode == 1 {
			return error(term.bright_red('Package not installed!'))
		}

		p := b_find_package_in_remotes(repos, name)!
		npk := b_download_package(localpath, p, name)!

		mut errl := 0
		for dep in npk.dependencies {
			m_install_package(dep, localpath, 0, false, fn () {}, update_succes, install_succes,
				fn [error_library] (lib string) {
				error_library(lib)
			}, repos) or {
				error_library(dep)
				errl++
			}
		}
		if errl > 0 {
			b_remove_pkg(p.all_after_last('/'), localpath) or {}
			return error(term.bright_red('Could not install ${errl} dependencies!'))
		}

		install_succes(npk.name, npk.version)
		return
	}

	p := b_find_package_in_remotes(repos, name)!

	pkf := b_get_pkg_from_text(http.get_text(p + '/pkg'))!
	if !update_if_dg && pk.version >= pkf.version {
		ifnot()
		return
	}

	npk := b_download_package(localpath, p, name)!

	mut errl := 0
	for dep in npk.dependencies {
		m_install_package(dep, localpath, 0, false, fn () {}, update_succes, install_succes,
			fn [error_library] (lib string) {
			error_library(lib)
		}, repos) or {
			error_library(dep)
			errl++
		}
	}
	if errl > 0 {
		b_remove_pkg(p.all_after_last('/'), localpath) or {}
		return error(term.bright_red('Could not install ${errl} dependencies!'))
	}

	update_succes(pk.name, pk.version, npk.version)
}

fn m_get_packages(path string, pkgs []string) ![]&Package {
	x := pkgs.map(fn [path] (x string) &Package {
		return m_get_installed_package(x, path) or { none }
	})
	if x.any(fn (x &Package) bool {
		return unsafe { x == 0 }
	})
	{
		return error('One or more packages not found!')
	}
	return x
}
