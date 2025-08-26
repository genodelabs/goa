##
# Depot-related actions and helpers
#

namespace eval goa {
	namespace export prepare_depot_with_apis prepare_depot_with_archives
	namespace export prepare_depot_with_debug_archives
	namespace export export-api export-raw export-src export-pkgs export-index
	namespace export export-dbg export-bin import-dependencies export-dependencies
	namespace export published-archives download-foreign publish archive-info

	proc exec_depot_tool { tool args } {
		global verbose gaol tool_dir
		global config::depot_dir config::public_dir config::jobs

		if {![file exists $public_dir]} {
			file mkdir $public_dir }

		set     cmd $gaol
		lappend cmd --system-usr
		lappend cmd --make
		lappend cmd --depot-dir $depot_dir
		lappend cmd --public-dir $public_dir
		lappend cmd --depot-tool [file join $tool_dir depot]

		switch $tool {
			dependencies { }
			download {
				lappend cmd --empty-gpg
				lappend cmd --with-network
			}
			publish {
				lappend cmd --user-gpg
			}
		}

		if {$verbose} {
			lappend cmd --verbose }

		lappend cmd [file join $tool_dir depot $tool]
		lappend cmd REPOSITORIES=

		if {$tool == "publish"} {
			exec -ignorestderr {*}$cmd -j$jobs {*}$args
		} else {
			exec {*}$cmd {*}$args
		}
	}

	##
	# Run `goa export` in specified project directory
	#
	proc export_dependent_project { dir arch { pkg_name "" } } {
		global argv0 config::jobs config::depot_user config::depot_dir
		global config::versions_from_genode_dir config::public_dir config::debug
		global config::common_var_dir config::var_dir verbose
		global config::search_dir

		set orig_pwd [pwd]
		cd $search_dir

		set cmd { }
		lappend cmd expect $argv0 export
		lappend cmd -C $dir
		lappend cmd --jobs $jobs
		lappend cmd --arch $arch
		lappend cmd --depot-user     $depot_user
		lappend cmd --depot-dir      $depot_dir
		lappend cmd --public-dir     $public_dir
		if {$common_var_dir != ""} {
			lappend cmd --common-var-dir $common_var_dir
		} else {
			lappend cmd --common-var-dir $var_dir
		}
		if {[info exists versions_from_genode_dir]} {
			lappend cmd --versions-from-genode-dir $versions_from_genode_dir
		}
		if {$verbose} {
			lappend cmd --verbose }
		if {$debug} {
			lappend cmd --debug }
		if {$pkg_name != ""} {
			lappend cmd --pkg $pkg_name }

		# keep existing exports of dependent projects untouched
		lappend cmd --depot-retain

		if {!$verbose} {
			log "exporting project $dir" }

		diag "exporting project $dir via cmd: $cmd"

		exec -ignorestderr {*}$cmd >@ stdout

		cd $orig_pwd

		return -code ok
	}


	proc download_archives { archives { no_err 0 } { dbg 0 }} {

		if {[llength $archives] > 0} {
			set args $archives
			if { $dbg } {
				lappend args "DBG=1" }

			diag "install depot archives: $archives"

			if { $no_err } {
				if {[catch { exec_depot_tool download {*}$args | sed "s/^Error://" >@ stdout }]} {
					return -code error }
			} else {
				if {[catch { exec_depot_tool download {*}$args >@ stdout }]} {
					return -code error }
			}
		}

		return -code ok
	}


	proc try_download_archives { archives } {
		return [download_archives $archives 1] }


	proc try_download_debug_archives { archives } {
		return [download_archives $archives 1 1] }


	##
	# Download api archives or export corresponding projects
	#
	proc prepare_depot_with_apis { } {

		global config::depot_user config::arch

		assert_definition_of_depot_user

		foreach used_api [used_apis] {
			archive_parts $used_api user type name vers
			if {$user != $depot_user} {
				continue }

			catch {
				set dir [find_project_dir_for_archive $type $name]

				# first, try downloading
				if {[catch { try_download_archives [list $used_api] }]} {
					if {"[exported_project_archive_version $dir $user/$type/$name]" != "$vers"} {
						log "skipping export of $dir due to version mismatch"
					} elseif {[catch {export_dependent_project $dir $arch} msg]} {
						exit_with_error "failed to export depot archive $used_api: \n\t$msg"
					}
				}
			}
		}
	}


	##
	# Download archives into depot
	#
	proc prepare_depot_with_archives { archive_list } {
		global config::depot_dir

		# create list of depot users without duplicates
		set depot_users { }
		foreach archive $archive_list {
			lappend depot_users [archive_user $archive] }
		set depot_users [lsort -unique $depot_users]

		# check if all depot users are present in the depot
		foreach user $depot_users {
			if {![file exists [file join $depot_dir $user]]} {
				exit_with_error "depot user '$user' is not known" \
				                "in depot at $depot_dir" } }

		# create list of uninstalled archives
		set uninstalled_archives { }
		foreach archive $archive_list {
			if {![file exists [file join $depot_dir $archive]]} {
				lappend uninstalled_archives $archive } }

		set uninstalled_archives [lsort -unique $uninstalled_archives]

		# download uninstalled archives
		if {[catch { download_archives $uninstalled_archives }]} {
			exit_with_error "failed to download the following depot archives:\n" \
			                [join $uninstalled_archives "\n "] }
	}


	##
	# Try downloading debug archives into depot
	#
	proc prepare_depot_with_debug_archives { archive_list } {
		global config::depot_dir

		set missing_debug_archives {}
		foreach archive $archive_list {
			set is_bin [regsub {/bin/} $archive {/dbg/} debug_archive]
			if { $is_bin && ![file exists [file join $depot_dir $debug_archive]]} {
				if {[catch { try_download_debug_archives [list $archive] }]} {
					lappend missing_debug_archives $debug_archive } }
		}

		if {[llength $missing_debug_archives]} {
			log "unable to download the following debug archives:\n" \
			    [join $missing_debug_archives "\n "] }
	}


	proc archive-info { archive } {
		global config::depot_dir tool_dir

		set archives [apply_versions [list $archive]]

		# download archive
		prepare_depot_with_archives $archives

		# look for README
		set versioned_archive [lindex $archives 0]
		archive_parts $versioned_archive user type name vers
		if {$type != "pkg" && $type != "bin" && $type != "src"} {
			exit_with_error "No info for archive type '$type' available." }

		set archive_path [file join $depot_dir $versioned_archive]
		if {$type == "bin"} {
			set archive_path [file join $depot_dir $user src $name $vers] }

		set find_cmd [list find $archive_path -type f -name README]
		if {$type == "pkg"} {
			lappend find_cmd -and -path "*/$vers/README"
		} else {
			lappend find_cmd -and -path "*/$name/README"
		}

		set candidates [exec {*}$find_cmd]
		if {[llength $candidates] == 0} {
			exit_with_error "Archive '$versioned_archive' does not contain a README file" }

		set     cmd [file join $tool_dir gosh gosh]
		lappend cmd --style man --style info --version $vers --archive $archive [lindex $candidates 0]| man -l -
		system {*}$cmd
	}


	##
	# Return versioned archive path for a project's archive of the specified type
	# (raw, src, pkg, bin, index)
	#
	proc versioned_project_archive { type { pkg_name ""} } {
	
		global config::depot_user config::project_dir config::project_name
		global config::version config::arch config::sculpt_version
	
		set name $project_name
	
		if {$type == "pkg" && $pkg_name != ""} {
			set name $pkg_name }
	
		assert_definition_of_depot_user
	
		if {$type == "index"} {
			if {$sculpt_version == ""} {
				exit_with_error "missing definition of sculpt version\n" \
				                "\n You can define the sculpt version by setting the 'sculpt_version'" \
				                "\n variable in a goarc file, or by specifing the '--sculpt-version <version>'"\
				                "\n command-line argument.\n" }
	
			return $depot_user/index/$sculpt_version
		}
	
		catch {
			set archive_version [project_version_from_file $project_dir]
		}
	
		#
		# If a binary archive is requested, try to obtain its version from
		# the corresponding source archive.
		#
		set binary_type ""
		if {$type == "bin" || $type == "dbg"} {
			set binary_type $type
			set type src
		}
	
		set archive "$depot_user/$type/$name"
	
		if {![info exists archive_version]} {
			if {[info exists version($archive)]} {
				set archive_version $version($depot_user/$type/$name) } }
	
		if {![info exists archive_version]} {
			exit_with_error "version for archive $archive undefined\n" \
			                "\n Create a 'version' file in your project directory, or" \
			                "\n define 'set version($archive) <version>' in your goarc file," \
			                "\n or specify '--version-$archive <version>' as argument.\n"
		}
	
		if {$binary_type != ""} {
			return "$depot_user/$binary_type/$arch/$name/$archive_version" }
	
		return "$depot_user/$type/$name/$archive_version"
	}
	
	
	##
	# Prepare destination directory within the depot
	#
	# \return path to the archive directory (or file if type=="index")
	#
	proc prepare_project_archive_directory { type { pkg_name "" } } {
		global config::depot_dir
	
		set policy [depot_policy]
		set archive [versioned_project_archive $type $pkg_name]
		set dst_dir "[file join $depot_dir $archive]"
	
		if {[file exists $dst_dir]} {
			if {$policy == "overwrite"} {
				file delete -force $dst_dir
			} elseif {$policy == "retain"} {
				log "retaining existing depot archive $archive"
				return ""
			} else {
				exit_with_error "archive $archive already exists in the depot\n" \
				                "\n You may specify '--depot-overwrite' to replace" \
				                "or '--depot-retain' to keep the existing version.\n"
			}
		}
	
		if {$type == "index"} {
			file mkdir [file dirname $dst_dir]
		} else {
			file mkdir $dst_dir
		}
		return $dst_dir
	}
	
	
	##
	# Return path to the license file as defined for the project
	#
	proc license_file { } {
		global config::project_dir config::license
	
		set local_license_file [file join $project_dir LICENSE]
		if {[file exists $local_license_file]} {
			return $local_license_file }
	
		if {![info exists license]} {
			exit_with_error "cannot export src or api archive because the license is undefined\n" \
			                "\n Create a 'LICENSE' file for the project, or" \
			                "\n define 'set license <path>' in your goarc file, or" \
			                "\n specify '--license <path>' as argument.\n"
		}
	
		if {![file exists $license]} {
			exit_with_error "license file $license does not exists" }
	
		return $license
	}
	
	
	##
	# Supplement index file pkg paths with user and version information
	#
	proc augment_index_versions { src_file dst_file } {
		global config::depot_user
	
		# read src_file
		set fd [open $src_file r]
		set content [read $fd]
		close $fd
	
		# filter 'path' attribute
		set pattern "(\<pkg\[^\>\]+?path=\")(\[^/\]+)(\")"
		while {[regexp $pattern $content dummy head pkg tail]} {
			set pkg_path [apply_versions $depot_user/pkg/$pkg]
			regsub $pattern $content "$head$pkg_path$tail" content
		}
	
		# write to dst_file
		set fd [open $dst_file w]
		puts $fd $content
		close $fd
	}


	proc export-api { } {

		global config::api_dir config::project_dir

		if {[file exists $api_dir] && [file isdirectory $api_dir]} {

			set license_file [license_file]

			set dst_dir [prepare_project_archive_directory api]
			if {$dst_dir != ""} {
				set files [exec find $api_dir -not -type d -and -not -name "*~"]
				foreach file $files {
					regsub "$api_dir/" $file "" file_dir
					set dir [file dirname $file_dir]
	
					# sanity check for include path
					set out_dir $dir
					set dir_parts [file split $dir]
					if { [llength $dir_parts] > 1 && \
					     [lindex $dir_parts 0] != "include" } {
						set idx 0
						set found 0
						foreach part $dir_parts {
							if {$part == "include"} {
								set found $idx
							}
							incr idx
						}
						if {$found == 0} {
							exit_with_error "no valid include path found in api artifacts."
						}
						set out_dir [file join [lrange $dir_parts $found [llength $dir_parts]]]
					}
					set target_dir [file join $dst_dir $out_dir]
					if {![file exists $target_dir]} {
						file mkdir $target_dir
					}
					file copy [file fullnormalize $file] [file join $target_dir [file tail $file]]
				}
	
				file mkdir [file join $dst_dir lib]
				if {[file exists [file join $project_dir "symbols"]]} {
					file copy [file join $project_dir "symbols"] [file join $dst_dir lib]
				}

				file copy $license_file [file join $dst_dir LICENSE]
	
				log "exported $dst_dir"
			}
		}
	}


	proc export-raw { } {

		global config::project_dir

		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			set dst_dir [prepare_project_archive_directory raw]
			if {$dst_dir != ""} {
				set files [exec find $raw_dir -not -type d -and -not -name "*~" -and -not -type l]
				foreach file $files {
					file copy $file [file join $dst_dir [file tail $file]] }
	
				log "exported $dst_dir"
			}
		}
	}


	proc export-src { } {

		global config::project_dir

		# create src archive
		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {
	
			set used_apis [apply_versions [read_file_content_as_list used_apis]]
	
			set files { }
			lappend files "src"
	
			foreach optional_file { artifacts import make_args cmake_args configure_args } {
				if {[file exists $optional_file]} {
					lappend files $optional_file } }
	
			set license_file [license_file]
	
			set dst_dir [prepare_project_archive_directory src]
			if {$dst_dir != ""} {
				foreach file $files {
					file copy $file [file join $dst_dir [file tail $file]] }
	
				file copy $license_file [file join $dst_dir LICENSE]
	
				exec find $dst_dir ( -name "*~" \
				                     -or -name "*.rej" \
				                     -or -name "*.orig" \
				                     -or -name "*.swp" ) -delete
	
				# generate 'used_apis' file with specific versions
				set fh [open [file join $dst_dir used_apis] "WRONLY CREAT TRUNC"]
				foreach api [used_apis] {
					puts $fh $api }
				close $fh
	
				log "exported $dst_dir"
			}
		}
	}


	proc export-pkgs { &exported_archives } {

		global args config::arch config::project_dir
		upvar  ${&exported_archives} exported_archives

		set pkg_expr "*"
		if {$args(publish_pkg) != ""} {
			set pkg_expr $args(publish_pkg) }
		set pkgs [glob -nocomplain -directory pkg -tail $pkg_expr -type d]
		foreach pkg $pkgs {
	
			set pkg_dir [file join pkg $pkg]
	
			set readme_file [file join $pkg_dir README]
			if {![file exists $readme_file]} {
				exit_with_error "missing README file at $readme_file" }
	
			set runtime_archives { }
	
			# automatically add the project's local raw and src archives
			set raw_dir [file join $project_dir raw]
			if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
				lappend runtime_archives [versioned_project_archive raw] }

			set src_dir [file join $project_dir src]
			if {[file exists $src_dir] && [file isdirectory $src_dir]} {
				lappend runtime_archives [versioned_project_archive src] }
	
			# add archives specified at the pkg's 'archives' file
			set archives_file [file join $pkg_dir archives]
			if {[file exists $archives_file]} {
				set runtime_archives [concat [read_file_content_as_list $archives_file] \
				                             $runtime_archives] }
	
			# supplement version info
			set runtime_archives [apply_versions $runtime_archives]
	
			set dst_dir [prepare_project_archive_directory pkg $pkg]
			if {$dst_dir != ""} {
				# copy content from pkg directory as is
				set files [exec find $pkg_dir -not -type d -and -not -name "*~" -and -not -type l]
				foreach file $files {
					file copy $file [file join $dst_dir [file tail $file]] }
	
				# overwrite exported 'archives' file with specific versions
				if {[llength $runtime_archives] > 0} {
					set fh [open [file join $dst_dir archives] "WRONLY CREAT TRUNC"]
					puts $fh [join $runtime_archives "\n"]
					close $fh
				}
	
				log "exported $dst_dir"
			}
	
			lappend exported_archives [apply_arch [versioned_project_archive pkg $pkg] $arch]
		}
	}


	proc export-bin { &exported_archives } {

		global config::bin_dir
		upvar  ${&exported_archives} exported_archives

		# create bin archive
		if {[file exists $bin_dir] && [file isdirectory $bin_dir]} {
			set dst_dir [prepare_project_archive_directory bin]
			if {$dst_dir != ""} {
				set files [glob -nocomplain -directory $bin_dir *]
				foreach file $files {
					set src_file [file fullnormalize $file]
					file copy $src_file [file join $dst_dir [file tail $file]] }
	
				log "exported $dst_dir"
			}
	
			lappend exported_archives [versioned_project_archive bin]
		}
	}


	proc export-dbg { } {

		global config::dbg_dir

		# create dbg archive
		if {[file exists $dbg_dir] && [file isdirectory $dbg_dir]} {
			set dst_dir [prepare_project_archive_directory dbg]
			if {$dst_dir != ""} {
				set files [glob -nocomplain -directory $dbg_dir *]
				foreach file $files {
					set src_file [file fullnormalize $file]
					file copy $src_file [file join $dst_dir [file tail $file]] }
	
				log "exported $dst_dir"
			}
		}
	}


	proc export-index { &exported_archives } {

		global config::project_dir config::depot_user config::depot_dir
		upvar  ${&exported_archives} exported_archives

		set index_file [file join $project_dir index]
		if {[file exists $index_file] && [file isfile $index_file]} {
			check_xml_syntax $index_file
	
			# check index file for any missing archives
			foreach { archive pkg_archs } [pkgs_from_index $index_file] {
	
				catch {
					set versioned_archive [lindex [apply_versions $archive] 0]
					set pkg_name [archive_name $archive]
	
					# download or export archive if it has not been exported
					set dst_dir "[file join $depot_dir $versioned_archive]"
					if {$dst_dir != "" && ![file exists $dst_dir]} {
						foreach pkg_arch $pkg_archs {
							# try downloading first
							if {![catch {try_download_archives [list [apply_arch $versioned_archive $pkg_arch]]}]} {
								continue }

							set dir {}
							catch { set dir [find_project_dir_for_archive pkg $pkg_name] }
							if {$dir == ""} {
								exit_with_error "unable to download or export missing archive $versioned_archive" }
	
							# check that the expected version matches the exported version
							set exported_archive_version [exported_project_archive_version $dir $archive]
							if { "$archive/$exported_archive_version" != "$versioned_archive" } {
								exit_with_error "unable to export $versioned_archive: project version is $exported_archive_version" }
	
							if {[catch { export_dependent_project $dir $pkg_arch $pkg_name } msg]} {
								exit_with_error "failed to export depot archive $archive: \n\t$msg" }
						}
	
					} elseif {$dst_dir != "" && [file exists $dst_dir]} {
						# mark arch-specific archives as exported to trigger dependency check
						foreach pkg_arch $pkg_archs {
							lappend exported_archives [apply_arch $versioned_archive $pkg_arch] }
					}
				}
			}
	
			set dst_file [prepare_project_archive_directory index]
			if {$dst_file != ""} {
				augment_index_versions $index_file $dst_file
				log "exported $dst_file"
			}
		}
	}


	proc import-dependencies { exported_archives &export_projects} {

		global tool_dir
		global config::depot_dir config::public_dir config::depot_user config::arch
		upvar  ${&export_projects} export_projects
	
		# determine dependent projects that need exporting
		foreach exported_archive $exported_archives {	
			diag "acquiring dependencies of exported depot archive: $exported_archive"
	
			set archives_incomplete 0
			if {[catch { exec_depot_tool dependencies $exported_archive 2> /dev/null } msg]} {
				foreach line [split $msg \n] {
					set archive [string trim $line]
					if {[catch {archive_parts $archive user type name vers}]} {
						continue
					}

					# transfer arch from $exported_archive
					if {$type == "pkg"} {
						archive_name_and_arch $exported_archive _name _arch
						set archive [apply_arch $archive $_arch]
					} elseif {$type == "src"} {
						archive_name_and_arch $exported_archive _name _arch
						set archive "$user/bin/$_arch/$name/$vers"
					}
	
					# try downloading before exporting
					if {![catch {try_download_archives [list $archive]}]} {
						continue }
	
					if {![catch {find_project_dir_for_archive $type $name} dir]} {
						if {$user != $depot_user} {
							log "skipping export of $dir: must be exported as depot user '$user'"
							continue
						}
	
						if {"[exported_project_archive_version $dir $user/$type/$name]" != "$vers"} {
							log "skipping export of $dir due to version mismatch"
							continue
						}
	
						set export_projects($archive) $dir
					} else {
						set archives_incomplete 1
						log "Unable to download or to find project directory for '$archive'"
					}
				}
			}
	
			if {$archives_incomplete} {
				exit_with_error "There are missing archives (see messages above)."
			}
		}

		puts [array names export_projects]
	}


	proc export-dependencies { &export_projects } {

		global config::arch
		upvar ${&export_projects} export_projects

		# export bin/pkg archives first and delay arch-independent archives
		set exported {}
		set remaining_archives {}
		foreach archive [array names export_projects] {
			set dir $export_projects($archive)
			archive_parts $archive user type name vers

			if {$type == "bin" || $type == "pkg"} {
				archive_name_and_arch $archive _pkg _arch

				if {[catch { export_dependent_project $dir $_arch $_pkg} msg]} {
					exit_with_error "failed to export project $dir: \n\t$msg" }

				lappend exported $dir
			} else {
				lappend remaining_archives $archive
			}
		}

		# export remaining arch-independent archives
		set exported [lsort -unique $exported]
		foreach archive $remaining_archives {
			set dir $export_projects($archive)

			# skip if project dir has been exported before
			if {[lsearch -exact $exported $dir] >= 0} { continue }

			if {[catch { export_dependent_project $dir $arch} msg]} {
				exit_with_error "failed to export project $dir: \n\t$msg" }

			lappend exported $dir
		}
	}


	proc published-archives { } {

		global args
		global config::project_dir config::bin_dir config::api_dir config::arch config::depot_dir
		set archives { }
		set index_archive ""
	
		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			lappend archives [versioned_project_archive raw] }
	
		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {
			lappend archives [versioned_project_archive src] }
	
		if {[file exists $bin_dir] && [file isdirectory $bin_dir]} {
			lappend archives [versioned_project_archive bin] }
	
		if {[file exists $api_dir] && [file isdirectory $api_dir]} {
			lappend archives [versioned_project_archive api] }
	
		if {$args(publish_pkg) != ""} {
			lappend archives [apply_arch [versioned_project_archive pkg $args(publish_pkg)] $arch]
		} else {
			set pkgs [glob -nocomplain -directory pkg -tail * -type d]
			foreach pkg $pkgs {
				lappend archives [apply_arch [versioned_project_archive pkg $pkg] $arch] }
		}
	
		set index_file [file join $project_dir index]
		if {[file exists $index_file] && [file isfile $index_file]} {
			set index_archive [versioned_project_archive index]
	
			#
			# add pkg paths found in index file to archives (adding arch part to
			# pkg path to make sure that the corresponding bin archives are
			# downloadable)
			#
			foreach { pkg_path pkg_archs } [pkgs_from_index [file join $depot_dir $index_archive]] {
				foreach pkg_arch $pkg_archs {
					lappend archives [apply_arch $pkg_path $pkg_arch] } }
		}

		return [list $archives $index_archive]
	}

	proc download-foreign { archives } {

		global tool_dir config::depot_dir config::public_dir config::depot_user

		set missing_archives ""
		if {[llength $archives] > 0} {

			diag "acquiring dependencies via archives: $archives"

			if {![catch { exec_depot_tool dependencies {*}$archives 2> /dev/null } msg]} {
				foreach line [split $msg \n] {
					set archive [string trim $line]
					if {[catch {archive_parts $archive user type name vers}]} {
						continue
					}
	
					if {$user == $depot_user} {
						continue
					}
	
					if {[file exists [file join $public_dir "$archive.tar.xz.sig"]]} {
						continue }

					diag "deleting $archive from depot to trigger re-download"
	
					# remove archive from depot_dir to trigger re-download
					file delete -force [file join $depot_dir $archive]
					lappend missing_archives $archive
				}
			} else {
				exit_with_error "\n$msg" }
		}
	
		# re-download missing archives
		set missing_archives [lsort -unique $missing_archives]
		if {[catch { download_archives $missing_archives }]} {
			exit_with_error "failed to download the following depot archives:\n" \
			                [join $missing_archives "\n "] }
	}


	proc publish { archives } {

		global tool_dir
		global config::debug

		if {[llength $archives] > 0} {
			set args $archives
			if { $debug } {
				lappend args "DBG=1" }
	
			diag "publish depot archives: $archives"
	
			if {[catch { exec_depot_tool publish {*}$args >@ stdout }]} {
				exit_with_error "failed to publish the following depot archives:\n" \
				                [join $archives "\n "] }
		}
	}
}
