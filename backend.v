module main

import os
import term
import net.http

struct Package {
	name string
	version int

	files []string

	remote string
	remotfiles []string

	desc string

	dependencies []string

	installed bool		// WARNING: not set by most functions
}

fn get_pkg_from_text(txt []string) !&Package {
	mut name := ""
	mut version := ""
	mut files := []string {}
	mut remote := "local"
	mut rfiles := []string {}
	mut desc := ""
	mut dep := []string {}

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
			"dep" { dep << a[1] }

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
		dependencies: dep
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
				v := "$remote/${b[1]}"
				if v.ends_with("/") {
					return v.all_before_last("/")
				}
				return v
			}
		}
	}
	return error(term.bright_red("Package not found in repos!"))
}

fn remove_pkg(dirname string) ! {
	if os.is_dir("/etc/spm/pkgs/$dirname") {
		pk := get_pkg_from_path("/etc/spm/pkgs/$dirname") or {
			os.rmdir_all("/etc/spm/pkgs/$dirname") or {
				return error(term.bright_red("Cannot delete package directory!"))
			}
			return
		}
		if os.is_file("/etc/spm/pkgs/$dirname/uninstall.sh") {
			os.chmod("/etc/spm/pkgs/$dirname/uninstall.sh", 777) or {
				return error(term.bright_red("Cannot make uninstall script executable!"))
			}
			os.chdir("/etc/spm/pkgs/$dirname/")!
			os.execute("bash /etc/spm/pkgs/$dirname/uninstall.sh")
		}
		os.rmdir_all("/etc/spm/pkgs/$dirname") or {
			return error(term.bright_red("Cannot delete package directory!"))
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

fn download_package(remote string) !&Package {
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
			return error(term.bright_red("Cannot make install script executable!"))
		}
		os.chdir("/etc/spm/pkgs/$dirname/")!
		os.execute("bash /etc/spm/pkgs/$dirname/install.sh")
	}

	return pk
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