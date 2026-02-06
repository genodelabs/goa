##
# Depot-related actions and helpers
#

namespace eval goa {
	namespace export prepare_depot_with_apis prepare_depot_with_archives
	namespace export prepare_depot_with_debug_archives
	namespace export export-api export-raw export-src export-pkg export-index
	namespace export export-dbg export-bin import-dependencies export-dependencies
	namespace export published-archives download-foreign publish archive-info
	namespace export update-index
	namespace export compare-src compare-raw compare-pkgs compare-api

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
		if {$depot_user != "_"} {
			lappend cmd --depot-retain }

		if {!$verbose} {
			log "exporting project $dir" }

		diag "exporting project $dir via cmd: $cmd"

		exec -ignorestderr {*}$cmd >@ stdout

		cd $orig_pwd

		return -code ok
	}


	proc missing_dependencies { archive } {
		set missing {}

		try {
			exec_depot_tool dependencies $archive 2> /dev/null

		} trap CHILDSTATUS { msg } {
			foreach line [split $msg \n] {
				set archive [string trim $line]
				try {
					archive_parts $archive user type name vers
					lappend missing $archive
				} trap INVALID_ARCHIVE { } {
					continue
				} on error { msg } { error $msg $::errorInfo }
			}

		} on error { msg } { error $msg $::errorInfo }
		
		return $missing
	}


	proc download_archives { archives args } {
		set no_err         0
		set dbg            0
		set force_download 0
		foreach arg $args {
			switch -exact $arg {
				dbg            { set dbg 1 }
				no_err         { set no_err 1 }
				force_download { set force_download 1 }
			}
		}

		# skip '_' archives
		set cmd_args [lmap archive $archives {
			if {![regexp {^_/.*} $archive]} {
				set archive
			} elseif {!$no_err} {
				return -code error -errorcode DOWNLOAD_FAILED ""
			} else { continue }
		}]

		if {[llength $cmd_args] > 0} {

			diag "install depot archives: $cmd_args"

			if { $dbg } {
				lappend cmd_args "DBG=1" }

			if { $force_download } {
				lappend cmd_args "FORCE_DOWNLOAD=1" }

			try {
				if { $no_err } {
					exec_depot_tool download {*}$cmd_args | sed "s/^Error://" >@ stdout
				} else {
					exec_depot_tool download {*}$cmd_args >@ stdout
				}

			} trap CHILDSTATUS { msg } {
				return -code error -errorcode DOWNLOAD_FAILED $msg

			} on error { msg info } { puts $info
					error $msg $::errorInfo }
		}

		return -code ok
	}


	proc try_download_archives { archives } {
		try {
			download_archives $archives "no_err"
			return 1
		} trap DOWNLOAD_FAILED {} {
			return 0
		} on error { msg } { error $msg $::errorInfo }
	}


	proc try_download_debug_archives { archives } {
		try {
			download_archives $archives "no_err" "dbg"
			return 1
		} trap DOWNLOAD_FAILED {} {
			return 0
		} on error { msg } { error $msg $::errorInfo }
	}


	##
	# Download api archives or export corresponding projects
	#
	proc prepare_depot_with_apis { } {

		global config::depot_user config::arch

		foreach used_api [used_apis] {
			archive_parts $used_api user type name vers
			if {$user != $depot_user} {
				continue }

			try {
				set dir [find_project_dir_for_archive $type $name]

				if {[try_download_archives [list $used_api]]} {
					continue }

				if {"[exported_project_archive_version $dir $user/$type/$name]" != "$vers"} {
					log "skipping export of $dir due to version mismatch"
				} else {
					export_dependent_project $dir $arch
				}

			} trap NOT_FOUND { } {
				# ignore if project dir was not found
				
			} trap CHILDSTATUS { msg } {
				# export failed
				exit_with_error "failed to export depot archive $used_api: \n\t$msg"

			} on error { msg } { error $msg $::errorInfo }
		}
	}


	##
	# Download archives into depot
	#
	proc prepare_depot_with_archives { archive_list } {
		global config::depot_dir config::arch

		# create list of depot users without duplicates
		set depot_users { }
		foreach archive $archive_list {
			lappend depot_users [archive_user $archive] }
		set depot_users [lsort -unique $depot_users]

		# check if all depot users are present in the depot
		foreach user $depot_users {
			set depot_user_dir [file join $depot_dir $user]
			if {![file exists $depot_user_dir]} {
				if {$user == "_"} {
					file mkdir $depot_user_dir
					continue
				}
				exit_with_error "depot user '$user' is not known" \
				                "in depot at $depot_dir"
			}
		}

		# create list of uninstalled archives
		set uninstalled_archives { }
		set wildcard_archives { }
		foreach archive $archive_list {
			if {![file exists [file join $depot_dir $archive]]} {
				if {[regexp {^_/.*} $archive]} {
					lappend wildcard_archives $archive
				} else {
					lappend uninstalled_archives $archive
				}
			}
		}

		set uninstalled_archives [lsort -unique $uninstalled_archives]
		set wildcard_archives    [lsort -unique $wildcard_archives]

		# export wildcard archives
		foreach archive $wildcard_archives {
			archive_parts $archive user type name vers
			try {
				set dir [find_project_dir_for_archive $type $name]

				if {"[exported_project_archive_version $dir $user/$type/$name]" != "$vers"} {
					log "skipping export of $dir due to version mismatch"
				} else {
					export_dependent_project $dir $arch
				}

			} trap NOT_FOUND { } {
				exit_with_error "unable to find project dir for exporting $archive"
				
			} trap CHILDSTATUS { msg } {
				# export failed
				exit_with_error "failed to export depot archive $archive \n\t$msg"

			} on error { msg } { error $msg $::errorInfo }
		}
	
		# download uninstalled archives
		try {
			download_archives $uninstalled_archives

		} trap DOWNLOAD_FAILED { } {
			exit_with_error "failed to download the following depot archives:\n" \
			                [join $uninstalled_archives "\n "]

		} on error { msg } { error $msg $::errorInfo }
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
				if {![try_download_debug_archives [list $archive]]} {
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
	
		if {$type == "index"} {
			if {$sculpt_version == ""} {
				exit_with_error "missing definition of sculpt version\n" \
				                "\n You can define the sculpt version by setting the 'sculpt_version'" \
				                "\n variable in a goarc file, or by specifing the '--sculpt-version <version>'"\
				                "\n command-line argument.\n" }
	
			return $depot_user/index/$sculpt_version
		}
	
		try {
			set archive_version [project_version_from_file $project_dir]
		} trap NOT_FOUND { } { #ignore
		} on error { msg } { error $msg $::errorInfo }
	
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
				set archive_version $version($archive)
			} elseif {[info exists version(_/$type/$name)]} {
				set archive_version $version(_/$type/$name)
			}
		}
	
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
	# Return list of versioned archives of exported pkg runtime
	# 
	proc versioned_runtime_archives { pkg } {
		global config::project_dir

		set runtime_archives { }

		# add archives specified at the pkg's 'archives' file
		set archives_file [file join pkg $pkg archives]
		if {[file exists $archives_file]} {
			set runtime_archives [apply_versions [read_file_content_as_list $archives_file]] }

		# automatically add the project's local raw and src archives
		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			lappend runtime_archives [versioned_project_archive raw] }

		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {
			lappend runtime_archives [versioned_project_archive src] }
		
		return $runtime_archives
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
		global config::hid

		proc _process_sub_index { node } {
			global config::depot_user

			set index_hid "+ index"
			node with-attribute $node "name" name {
				append index_hid " $name"
			} default { }

			node with-attribute $node "arch" arch {
				append index_hid " | arch: $arch"
			} default { }

			set result [hid create $index_hid]
			node for-all-nodes $node node_type subnode {
				switch -exact $node_type {
					api -
					src -
					pkg {
						node with-attribute $subnode "path" path {
							try {
								archive_parts $path user type name vers
								set archive $path
							} trap INVALID_ARCHIVE { } {
								set archive "$depot_user/$node_type/$path"
							} on error { msg } { error $msg $::errorInfo }

							set tmp "  + $node_type | path: [apply_versions $archive]"
							node with-attribute $subnode "info" info {
								append tmp " | info: $info"
							} default { }

							node with-attribute $subnode "arch" arch {
								append tmp " | arch: $arch"
							} default { }

							hid append result $tmp
						} default { }
					}
					supports {
						node with-attribute $subnode "arch" arch {
							hid append result "  + supports | arch: $arch"
						} default { }
					}
					index {
						hid append result [hid indent 1 [_process_sub_index $subnode]]
					}
				}
			}
			return $result
		}

		set data [_process_sub_index [query node $src_file "index"]]

		set fd [open $dst_file "w"]
		if {$hid} {
			puts $fd [hid as_string [hid format $data]]
		} else {
			puts $fd [join [hid format-xml $data] "\n"]
		}
		close $fd
	}


	proc export-api { { dst_dir "" } } {

		global config::api_dir config::project_dir

		if {[file exists $api_dir] && [file isdirectory $api_dir]} {

			set license_file [license_file]

			set silent 1
			if {$dst_dir == ""} {
				set dst_dir [prepare_project_archive_directory api]
				set silent 0
			}

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
	
				if {!$silent} {
					log "exported $dst_dir" }
			}
		}
	}


	proc export-raw { { dst_dir "" } } {

		global config::project_dir

		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			if {$dst_dir == ""} {
				set dst_dir [prepare_project_archive_directory raw] }
			if {$dst_dir != ""} {
				set files [exec find $raw_dir -not -type d -and -not -name "*~" -and -not -type l]
				foreach file $files {
					file copy $file [file join $dst_dir [file tail $file]] }
	
				log "exported $dst_dir"
			}
		}
	}


	proc export-src { { dst_dir "" } } {

		global config::project_dir

		# create src archive
		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {

			set files { }
			lappend files "src"
	
			foreach optional_file { artifacts import make_args cmake_args configure_args } {
				if {[file exists $optional_file]} {
					lappend files $optional_file } }
	
			set license_file [license_file]
	
			set silent 1
			if {$dst_dir == ""} {
				set dst_dir [prepare_project_archive_directory src]
				set silent 0
			}

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
	
				if {!$silent} {
					log "exported $dst_dir" }
			}
		}
	}


	proc export-pkg { pkg &exported_archives { dst_dir "" }} {

		global args tool_dir config::arch config::project_dir
		upvar  ${&exported_archives} exported_archives

		set pkg_dir [file join pkg $pkg]

		set readme_file [file join $pkg_dir README]
		if {![file exists $readme_file]} {
			exit_with_error "missing README file at $readme_file" }

		# check runtime file against hsd
		set runtime_file [file join $pkg_dir runtime]
		if {[file exists $runtime_file]} {
			try {
				hid tool $runtime_file check --hsd-dir [file join $tool_dir hsd] --schema runtime
			} trap CHILDSTATUS { msg } {
				exit_with_error "Schema validation failed for $runtime_file:\n$msg"
			} on error { msg } { error $msg $::errorInfo }
		}

		set runtime_archives [versioned_runtime_archives $pkg]

		set silent 1
		if {$dst_dir == ""} {
			set dst_dir [prepare_project_archive_directory pkg $pkg]
			set silent 0
		}

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

			if {!$silent} {
				log "exported $dst_dir" }
		}

		lappend exported_archives [apply_arch [versioned_project_archive pkg $pkg] $arch]
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


	proc update-index { user } {
		global config::sculpt_version config::depot_dir config::public_dir
		global config::depot_user

		if {$user == "_"} {
			return }

		# remove index from depot_dir and public_dir to trigger redownload
		if {$user != $depot_user} {
			set public_path [file join $public_dir $user index]
			set depot_path  [file join $depot_dir  $user index]

			if {[file exists [file join $public_path $sculpt_version.xz.sig]]} {
				file delete -force [file join $public_path $sculpt_version.xz]
				file delete -force [file join $public_path $sculpt_version.xz.sig]
				file delete -force [file join $depot_path  $sculpt_version]
			}
		}

		try_download_archives [list $user/index/$sculpt_version]
	}


	proc export-index { &exported_archives } {

		global config::project_dir config::depot_dir
		upvar  ${&exported_archives} exported_archives

		# helper for downloading archives and exporting projects
		proc _make_archive_available { versioned_archive archive_arch } {
			global config::depot_user

			archive_parts $versioned_archive user type name vers

			# try downloading first
			if {[try_download_archives [list [apply_arch $versioned_archive $archive_arch]]]} {
				return }

			# do not continue if archive user does not match the current depot user
			if { $depot_user != $user } {
				exit_with_error "unable to download missing archive $versioned_archive" }

			# try to find corresponding project and export
			try {
				set dir [find_project_dir_for_archive $type $name]
				
				# check that the expected version matches the exported version
				set exported_archive_version [exported_project_archive_version $dir $user/$type/$name]
				if { "$archive/$exported_archive_version" != "$versioned_archive" } {
					exit_with_error "unable to export $versioned_archive: project version is $exported_archive_version" }


				set pkg_name ""
				if {$type == "pkg"} {
					set pkg_name $name }
				export_dependent_project $dir $archive_arch $pkg_name

			} trap NOT_FOUND { } {
				# project dir not found
				exit_with_error "unable to download or export missing archive $versioned_archive"

			} trap CHILDSTATUS { msg } {
				# export failed
				exit_with_error "failed to export depot archive $versioned_archive: \n\t$msg"

			} on error { msg } { error $msg $::errorInfo }
		}

		set index_file [file join $project_dir index]
		if {[file exists $index_file] && [file isfile $index_file]} {
			query validate-syntax $index_file
	
			# check index file for any missing archives
			foreach { archive archs } [from-index $index_file "pkg" "src" "api"] {
	
				set versioned_archive [lindex [apply_versions $archive] 0]
				archive_parts $versioned_archive user type name vers

				# make binary archives available
				if {$type == "src"} {
					foreach $archive_arch $archs {
						set dst_dir "[file join $depot_dir [apply_arch $versioned_archive $archive_arch]]"
						if {$dst_dir != "" && ![file exists $dst_dir]} {
							_make_archive_available $versioned_archive $archive_arch }
					}
				}

				# download missing api and src archives or export for any architecture
				if {$type == "api" || $type == "src"} {
					set dst_dir "[file join $depot_dir $versioned_archive]"
					if {$dst_dir != "" && ![file exists $dst_dir]} {
						_make_archive_available $versioned_archive [lindex $archs 0]}
				}

				# download or export missing pkg archives
				if {$type == "pkg"} {
					set dst_dir "[file join $depot_dir $versioned_archive]"
					if {$dst_dir != "" && ![file exists $dst_dir]} {

						foreach archive_arch $archs {
							_make_archive_available $versioned_archive $archive_arch }

					} elseif {$dst_dir != "" && [file exists $dst_dir]} {

						# mark arch-specific archives as exported to trigger dependency check
						foreach archive_arch $archs {
							lappend exported_archives [apply_arch $versioned_archive $archive_arch] }

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
			foreach archive [missing_dependencies $exported_archive] {
				archive_parts $archive user type name vers
				
				# transfer arch from $exported_archive
				if {$type == "pkg"} {
					archive_name_and_arch $exported_archive _name _arch
					set archive [apply_arch $archive $_arch]
				} elseif {$type == "src"} {
					archive_name_and_arch $exported_archive _name _arch
					set archive "$user/bin/$_arch/$name/$vers"
				}

				# try downloading before exporting
				if {[try_download_archives [list $archive]]} {
					continue }

				try {
					set dir [find_project_dir_for_archive $type $name]

					if {$user != $depot_user} {
						log "skipping export of $dir: must be exported as depot user '$user'"
						continue
					}

					if {"[exported_project_archive_version $dir $user/$type/$name]" != "$vers"} {
						log "skipping export of $dir due to version mismatch"
						continue
					}

					set export_projects($archive) $dir

				} trap NOT_FOUND { } {
					set archives_incomplete 1
					log "Unable to download or to find project directory for '$archive'"

				} on error { msg } { error $msg $::errorInfo }

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
	
			foreach { path archs } [from-index [file join $depot_dir $index_archive] "pkg" "src"] {
				foreach archive_arch $archs {
					lappend archives [apply_arch $path $archive_arch] } }

			foreach { path archs } [from-index [file join $depot_dir $index_archive] "api"] {
				lappend archives $path }
		}

		return [list $archives $index_archive]
	}

	proc download-foreign { archives } {

		global tool_dir config::depot_dir config::public_dir config::depot_user

		set missing_archives ""
		if {[llength $archives] > 0} {

			diag "acquiring dependencies via archives: $archives"

			try {
				set output [exec_depot_tool dependencies {*}$archives 2> /dev/null]
				foreach line [split $output \n] {
					set archive [string trim $line]
					try {
						archive_parts $archive user type name vers
					} trap INVALID_ARCHIVE { } {
						continue
					} on error { msg } { error $msg $::errorInfo }
	
					if {$user == $depot_user} {
						continue
					}
	
					if {[file exists [file join $public_dir "$archive.tar.xz.sig"]]} {
						continue }

					lappend missing_archives $archive
				}
			} trap CHILDSTATUS { msg } {
				exit_with_error "Failed to acquire dependencies of archives: $archives\n$msg"
			} on error { msg } { error $msg $::errorInfo }
		}
	
		# re-download missing archives
		set missing_archives [lsort -unique $missing_archives]
		try {
			download_archives $missing_archives "force_download"

		} trap DOWNLOAD_FAILED { } {
			exit_with_error "failed to download the following depot archives:\n" \
			                [join $missing_archives "\n "]

		} on error { msg } { error $msg $::errorInfo }
	}


	proc publish { archives } {

		global tool_dir
		global config::debug

		if {[llength $archives] > 0} {
			set args $archives
			if { $debug } {
				lappend args "DBG=1" }
	
			diag "publish depot archives: $archives"
	
			try {
				exec_depot_tool publish {*}$args >@ stdout
			} trap CHILDSTATUS { } {
				exit_with_error "failed to publish the following depot archives:\n" \
				                [join $archives "\n "]
			} on error { msg } { error $msg $::errorInfo }
		}
	}


	proc download_if_missing { archive } {
		global config::depot_dir config::public_dir args

		if {![file exists [file join $depot_dir $archive]]} {
			try {
				download_archives $archive

			} trap DOWNLOAD_FAILED { } {
					exit_with_error "failed to download $archive"

			} on error { msg } { error $msg $::errorInfo }
		}

		if {$args(force_download)} {
			if {![file exists [file join $public_dir $archive.tar.xz.sig]]} {
				try {
					download_archives $archive "force_download" "no_err"

				} trap DOWNLOAD_FAILED { } {
				} on error { msg } { error $msg $::errorInfo }
			}
		}
	}


	proc compare-raw { &exported_archives } {
		global config::depot_dir config::project_dir

		upvar ${&exported_archives} exported_archives
		
		set raw_dir [file join $project_dir raw]
		if {[file exists $raw_dir] && [file isdirectory $raw_dir]} {
			set other_archive [versioned_project_archive raw]
			download_if_missing $other_archive
			set other_dir [file join $depot_dir $other_archive]

			set status [exec_status [list diff -qNr raw $other_dir > /dev/null]]
			if {$status != 0} {
				log "$other_archive differs from current project state"
				return false
			}

			lappend exported_archives $other_archive
		}

		return true
	}


	proc compare-src { &exported_archives } {
		global config::depot_dir config::project_dir config::project_name

		upvar ${&exported_archives} exported_archives
		
		set src_dir [file join $project_dir src]
		if {[file exists $src_dir] && [file isdirectory $src_dir]} {
			set other_archive [versioned_project_archive src]
			download_if_missing $other_archive
			set other_dir [file join $depot_dir $other_archive]

			set dst_dir [file join $depot_dir _ src $project_name compare]
			file delete -force $dst_dir
			file mkdir $dst_dir
			export-src $dst_dir

			set status [exec_status [list diff -qNr $dst_dir $other_dir > /dev/null]]
			file delete -force $dst_dir
			if {$status != 0} {
				log "$other_archive differs from current project state"
				return false
			}

			lappend exported_archives $other_archive
		}

		return true
	}


	proc compare-pkgs { pkg_expr &exported_archives } {
		global config::depot_dir config::project_dir config::project_name

		upvar ${&exported_archives} exported_archives

		set result true
		for_each_pkg pkg $pkg_expr {
			set pkg_dir [file join pkg $pkg]

			set other_archive [versioned_project_archive pkg $pkg]
			download_if_missing $other_archive
			set other_dir [file join $depot_dir $other_archive]

			set dst_dir [file join $depot_dir _ pkg $pkg compare]
			file delete -force $dst_dir
			file mkdir $dst_dir

			set dummy ""
			export-pkg $pkg dummy $dst_dir

			set status [exec_status [list diff -qNr $dst_dir $other_dir > /dev/null]]
			file delete -force $dst_dir
			if {$status != 0} {
				log "$other_archive differs from current project state"
				set result false
			}

			lappend exported_archives $other_archive
		}

		return $result
	}


	proc compare-api { &exported_archives } {
		global config::depot_dir config::api_dir config::project_dir
		global config::project_name

		upvar ${&exported_archives} exported_archives
 
		if {[file exists $api_dir] && [file isdirectory $api_dir]} {
			set other_archive [versioned_project_archive api]
			download_if_missing $other_archive
			set other_dir [file join $depot_dir $other_archive]

			set dst_dir [file join $depot_dir _ api $project_name compare]
			file delete -force $dst_dir
			file mkdir $dst_dir
			export-api $dst_dir

			set status [exec_status [list diff -qNr $dst_dir $other_dir > /dev/null]]
			file delete -force $dst_dir
			if {$status != 0} {
				log "$other_archive differs from current project state"
				return false
			}

			lappend exported_archives $other_archive

		} elseif {[file exists [file join $project_dir api]]} {
			log "skipping comparison with api archive - please execute 'goa build' first"
		}

		return true
	}
}
