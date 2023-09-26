module main

import os
import term
import net.http

struct Package {
	name    string
	version int

	files []string

	remote     string
	remotfiles []string

	desc string

	dependencies []string

	installed bool // WARNING: not set by most functions
}

fn cmp_u8a_am_nt(a &u8, b &u8, amount int) bool {
	unsafe {
		for i := 0; i < amount; i++ {
			if a[i] == 0 || b[i] == 0 {
				return false
			}
			if a[i] != b[i] {
				return false
			}
		}
		return true
	}
}

fn b_get_pkg_from_text(txtIn string) !&Package {
	txt := txtIn.clone()
	mut name := ''
	mut version := ''
	mut files := []string{}
	mut remote := 'local'
	mut rfiles := []string{}
	mut desc := ''
	mut dep := []string{}

	mut lastoff := 0
	for i, c in txt {
		if c == c'\n' {
			unsafe {
				*(txt.str + i) = c'\0'
			}
			unsafe {
				l := (txt.str + lastoff)

				if *l == 0 || *l == c' ' {
					continue
				}

				if cmp_u8a_am_nt(l, c'name<', 5) {
					name = (l + 5).vstring()
				} else if cmp_u8a_am_nt(l, c'version<', 8) {
					version = (l + 8).vstring()
				} else if cmp_u8a_am_nt(l, c'file<', 5) {
					files << (l + 5).vstring()
				} else if cmp_u8a_am_nt(l, c'remote<', 7) {
					remote = (l + 7).vstring()
				} else if cmp_u8a_am_nt(l, c'rfile<', 6) {
					rfiles << (l + 6).vstring()
				} else if cmp_u8a_am_nt(l, c'desc<', 5) {
					desc = (l + 5).vstring()
				} else if cmp_u8a_am_nt(l, c'dep<', 4) {
					dep << (l + 4).vstring()
				} else {
					return error(term.bright_red('Corrupted pkg file!'))
				}
			}
			lastoff = i + 1
		}
	}

	unsafe {
		l := (txt.str + lastoff)

		if *l == 0 || *l == c' ' {
			goto eusf
		}

		if cmp_u8a_am_nt(l, c'name<', 5) {
			name = (l + 5).vstring()
		} else if cmp_u8a_am_nt(l, c'version<', 8) {
			version = (l + 8).vstring()
		} else if cmp_u8a_am_nt(l, c'file<', 5) {
			files << (l + 5).vstring()
		} else if cmp_u8a_am_nt(l, c'remote<', 7) {
			remote = (l + 7).vstring()
		} else if cmp_u8a_am_nt(l, c'rfile<', 6) {
			rfiles << (l + 6).vstring()
		} else if cmp_u8a_am_nt(l, c'desc<', 5) {
			desc = (l + 5).vstring()
		} else if cmp_u8a_am_nt(l, c'dep<', 4) {
			dep << (l + 4).vstring()
		} else {
			return error(term.bright_red('Corrupted pkg file!'))
		}
	}
	eusf:
	v := version.int()
	if v == 0 {
		return error(term.bright_red('Invalid package version! Only ints > 0 allowed!'))
	}

	return &Package{
		name: name
		version: v
		files: files
		remote: remote
		remotfiles: rfiles
		desc: desc
		dependencies: dep
	}
}

fn b_get_pkg_from_path(path string) !&Package {
	if !os.is_readable(path + '/pkg') {
		return error(term.bright_red('Not readable!'))
	}

	return b_get_pkg_from_text(os.read_file(path + '/pkg')!)
}

fn b_get_pkg_path_from_cache(cache []string, pkg string) !string {
	for cp in cache {
		a := cp.split('=')
		if a[0] == pkg {
			return a[1]
		}
	}
	return error('Package not found!')
}

// b_find_package_in_remotes returns the url of the path to the package on any remote OR an error if it doesnt exist
fn b_find_package_in_remotes(remotes []string, pkg string) !string {
	for remote in remotes {
		a := http.get_text('${remote}/pkcache')
		if a == '' {
			continue
		}
		for ci in a.split('\n') {
			if ci.len == 0 {
				continue
			}
			b := ci.split('=')
			if b[0] == pkg {
				v := '${remote}/${b[1]}'
				if v.ends_with('/') {
					return v.all_before_last('/')
				}
				return v
			}
		}
	}
	return error(term.bright_red('Package not found in repos!'))
}

fn b_remove_pkg(dirname string, path string) ! {
	if os.is_dir('${path}/${dirname}') {
		pk := b_get_pkg_from_path('${path}/${dirname}') or {
			os.rmdir_all('${path}/${dirname}') or {
				return error(term.bright_red('Cannot delete package directory!'))
			}
			return
		}
		if os.is_file('${path}/${dirname}/uninstall.sh') {
			os.chmod('${path}/${dirname}/uninstall.sh', 777) or {
				return error(term.bright_red('Cannot make uninstall script executable!'))
			}
			os.chdir('${path}/${dirname}/')!
			os.execute('bash ${path}/${dirname}/uninstall.sh')
		}
		os.rmdir_all('${path}/${dirname}') or {
			return error(term.bright_red('Cannot delete package directory!'))
		}
		if dirname != 'spm' {
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

	cache := os.read_lines('${path}/pkcache') or { return }
	mut newcache := []string{}
	for cp in cache {
		a := cp.split('=')
		if dirname != a[1] {
			newcache << cp
		}
	}
	os.write_file('${path}/pkcache', newcache.join('\n')) or {}
}

fn b_download_package(path string, remote string) !&Package {
	mut dirname := remote.all_after_last('/')
	if remote.ends_with('/') {
		dirname = remote#[..-1].all_after_last('/')
	}
	b_remove_pkg(dirname, path)!
	pkf := http.get_text(remote + '/pkg')
	pk := b_get_pkg_from_text(pkf) or { return error(term.bright_red('Remote url not a package!')) }
	os.mkdir(path + '/${dirname}/') or {
		return error(term.bright_red('Error creating dir for pkg!'))
	}
	os.write_file(path + '/${dirname}/pkg', pkf) or {
		return error(term.bright_red('No permissions to install package!'))
	}
	for rfile in pk.remotfiles {
		os.write_file(path + '/${dirname}/${rfile}', http.get_text(remote + '/${rfile}')) or {}
	}

	mut cache := os.read_lines(path + '/pkcache') or {
		return error(term.bright_red('Package cache broken!'))
	}
	cache << pk.name + '=' + dirname
	os.write_file(path + '/pkcache', cache.join('\n')) or {
		return error(term.bright_red('No permissions to install package!'))
	}

	if os.is_file(path + '/${dirname}/install.sh') {
		os.chmod(path + '/${dirname}/install.sh', 777) or {
			return error(term.bright_red('Cannot make install script executable!'))
		}
		os.chdir(path + '/${dirname}/')!
		os.execute('bash ${path}/${dirname}/install.sh')
	}

	return pk
}

fn (arr []&Package) tostring() []string {
	return arr.map(fn (pk &Package) string {
		return pk.name
	})
}

fn all_after_first_no_clone(s string, c u8) string {
	index := s.index_u8(c)
	if index == -1 {
		return ''
	}
	pt := unsafe { s.str + index + 1 }
	return unsafe { pt.vstring() }
}

[unsafe]
fn before_ctrl_codes_modify(s &u8) {
	unsafe {
		mut i := 0
		for *(s + i) != c'\0' {
			match *(s + i) {
				c'\0' {
					break
				}
				c'\n' {
					*(s + i) = c'\0'
					break
				}
				c'\t' {
					*(s + i) = c'\0'
					break
				}
				c'\v' {
					*(s + i) = c'\0'
					break
				}
				c'\f' {
					*(s + i) = c'\0'
					break
				}
				c'\r' {
					*(s + i) = c'\0'
					break
				}
				else {}
			}
			i += 1
		}
	}
}

[unsafe]
fn all_before_first_modify_arg(s string, c u8) string {
	index := s.index_u8(c)
	if index == -1 {
		return s
	}
	unsafe {
		*(s.str + index) = c'\0'
	}
	return unsafe { s.str.vstring() }
}

fn cstr_index_u8(s &u8, c u8) int {
	unsafe {
		mut i := 0
		for *(s + i) != c'\0' {
			if *(s + i) == c {
				return i
			}
			i += 1
		}
		return -1
	}
}

[unsafe]
fn all_before_first_modify_fast(s &u8, c u8) {
	index := cstr_index_u8(s, c)
	if index == -1 {
		return
	}
	unsafe {
		*(s + index) = c'\0'
	}
}

fn b_updateable_pkgs_list(path string, repos []string) []&Package {
	mut upa := []&Package{}

	for pkgf in os.read_lines(path + '/pkcache') or { return upa } {
		pkg := all_after_first_no_clone(pkgf, c'=')
		if !os.is_file(path + '/${pkg}/pkg') {
			continue
		}
		pk := b_get_pkg_from_path(path + '/${pkg}') or { continue }

		if pk.remote != 'local' {
			remotetxt := http.get_text(pk.remote + '/pkg')
			if remotetxt != '' {
				rpk := b_get_pkg_from_text(remotetxt) or { continue }
				if rpk.version > pk.version {
					upa << &Package{
						name: unsafe {
							all_before_first_modify_arg(pkgf, c'=')
						} // not real name! (is directory name)
						remote: pk.remote
					}
				}
				continue
			}
		}
		pa := b_find_package_in_remotes(repos, pkg) or { continue }
		remotetxt := http.get_text(pa + '/pkg')
		if remotetxt != '' {
			rpk := b_get_pkg_from_text(remotetxt) or { continue }
			if rpk.version > pk.version {
				upa << &Package{
					name: unsafe {
						all_before_first_modify_arg(pkgf, c'=')
					} // not real name! (is directory name)
					remote: pa
				}
			}
			continue
		}
	}

	return upa
}
