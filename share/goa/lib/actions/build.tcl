##
# Build action and helpers
#

namespace eval goa {
	namespace export build-dir build using_api used_apis check_abis
	namespace export build extract_artifacts_from_build_dir extract_api_artifacts
	namespace export extract-abi-symbols

	##
	# Return type of build system used in the source directory
	#
	proc detect_build_system { } {

		# XXX autoconf (configure.ac)
		# XXX autoconf (configure.ac configure), e.g., bash
		# XXX custom configure (no configure.ac configure), e.g., Vim
		# XXX Genode build system (src dir, any target.mk)

		if {[file exists [file join src CMakeLists.txt]]} {
			return cmake }

		if {[file exists [file join src configure]]} {
			return autoconf }

		#
		# If there is only the configure.ac file, it's an autoconf project
		# but autoreconf has to be called first in order to generate the
		# configure file.
		#
		if {[file exists [file join src configure.ac]]} {
			return autoconf }

		if {[file exists [glob -nocomplain [file join src *.pro]]]} {
			return qmake }

		if {[file exists [file join src Makefile]]} {
			return make }

		if {[file exists [file join src Cargo.toml]]} {
			return cargo }

		if {[file exists [file join src makefile]]} {
			return make }

		if {[file exists [file join src vivado.tcl]]} {
			return vivado }

		if {[file exists [file join src meson.build]]} {
			return meson }

		exit_with_error "unable to determine build system for [pwd]"
	}


	proc gaol_with_toolchain { {silent 0} } {

		global   gaol verbose allowed_tools

		set     cmd $gaol
		lappend cmd --system-usr

		foreach dir [lsearch -all -inline -not $allowed_tools /usr*] {
			lappend cmd --ro-bind $dir }

		if {$verbose && !$silent} {
			lappend cmd --verbose }

		return $cmd
	}


	proc exec_tool_chain { bin args } {

		global config::cross_dev_prefix config::build_dir

		set cmd [gaol_with_toolchain 1]

		if {[file exists $build_dir]} {
			lappend cmd --bind $build_dir }

		lappend cmd $cross_dev_prefix$bin

		exec {*}$cmd {*}$args
	}


	proc used_apis { } {

		variable _used_apis

		if {![info exists _used_apis]} {
			set _used_apis [apply_versions [read_file_content_as_list used_apis]]
			if {[llength $_used_apis] > 0} {
				diag "used APIs: $_used_apis" }
		}

		return $_used_apis
	}

	##
	# strip debug symbols from binary
	#
	proc strip_binary { file } {
		catch { exec_tool_chain strip "$file" }
	}


	##
	# extract debug info files
	#
	proc extract_debug_info { file } {

		##
		# check whether file has debug info and bail if not
		#

		if {[catch { exec_tool_chain objdump -hj .debug_info "$file" }]} {
			diag "file \"$file\" has no debug info"
			return }

		##
		# create debug info file
		#
			#
		if {[catch { exec_tool_chain objcopy --only-keep-debug "$file" "$file.debug" }]} {
			diag "unable to extract debug info file from $file"
			return
		}

		##
		# add gnu_debuglink section to binary
		#

		# change dir because --add-gnu-debuglink expect .debug file in working dir
		set filename [file tail $file]
		set orig_pwd [pwd]
		cd [file dirname $file]

		if {[catch { exec_tool_chain objcopy --add-gnu-debuglink=$filename.debug $filename }]} {
			diag "unable to add gnu_debuglink section to $file" }

		cd $orig_pwd
	}


	##
	# Return 1 if specified API is used
	#
	proc using_api { api } {

		foreach used_api [used_apis] {
			if {[archive_name $used_api] == $api} {
				return 1 } }
		return 0
	}

	##
	# Generate API stubs
	#
	proc prepare_abi_stubs { used_apis } {

		global tool_dir verbose
		global config::depot_dir config::abi_dir config::cross_dev_prefix
		global config::ld_march config::cc_march config::project_name config::arch

		set     cmd "make -f $tool_dir/lib/gen_abi_stubs.mk"
		lappend cmd "TOOL_DIR=$tool_dir"
		lappend cmd "DEPOT_DIR=$depot_dir"
		lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
		lappend cmd "APIS=[join $used_apis { }]"
		lappend cmd "ABI_DIR=$abi_dir"
		lappend cmd "ARCH=$arch"
		lappend cmd "LD_MARCH=[join $ld_march { }]"
		lappend cmd "CC_MARCH=[join $cc_march { }]"
		if {$verbose == 0} {
			lappend cmd "-s" }

		diag "generate ABI stubs via command: [join $cmd { }]"

		if {[catch { exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:abi\] /" >@ stdout }]} {
			exit_with_error "failed to generate ABI stubs for the following" \
			                "depot archives:\n" [join $used_apis "\n "] }
	}
	

	##
	# Generate ldso_support.lib.a if required
	#
	proc prepare_ldso_support_stub { used_apis } {

		global tool_dir verbose
		global config::depot_dir config::abi_dir config::cross_dev_prefix
		global config::cc_march config::project_name config::arch

		set so_api { }
		foreach api_path $used_apis {
			set parts [file split $api_path]
			set api [lindex $parts 2]
			if {[string compare $api "so"] == 0} {
				lappend so_api $api_path
			}
		}

		if {[llength $so_api] == 0} {
			return }

		set     cmd "make -f $tool_dir/lib/gen_ldso_support.mk"
		lappend cmd "TOOL_DIR=$tool_dir"
		lappend cmd "DEPOT_DIR=$depot_dir"
		lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
		lappend cmd "APIS=[join $so_api { }]"
		lappend cmd "ABI_DIR=$abi_dir"
		lappend cmd "CC_MARCH=[join $cc_march { }]"
		if {$verbose == 0} {
			lappend cmd "-s" }

		diag "generate ldso_support.lib.a via command: [join $cmd { }]"

		if {[catch { exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:abi\] /" >@ stdout }]} {
			exit_with_error "failed to generate ldso_support.lib.a "] }
	}

	##
	# Implements 'goa build-dir' command
	#
	proc build-dir { } {

		global tool_dir
		global config::cross_dev_prefix config::depot_dir config::rebuild
		global config::arch config::olevel config::cc_march config::debug
		global config::cc_cxx_opt_std config::ld_march config::abi_dir
		global config::build_dir api_dirs
		global config::with_backtrace config::warn_strict config::depot_user
		global config::project_name config::project_dir

		#
		# Check for availability of the Genode tool chain
		#
		if {![have_installed ${cross_dev_prefix}gcc]} {
			exit_with_error "the tool chain ${cross_dev_prefix}" \
			                 "is required but not installed." \
			                 "Please refer to https://genode.org/download/tool-chain" \
			                 "for more information."
		}

		#
		# Prepare depot content for the used APIs and generate ABI stubs
		#
		# This must happen before assembling the compile flags and creating /
		# configuring the build directory so that the build system's automatic
		# configuration magic finds the APIs and libraries.
		#
		prepare_depot_with_archives [used_apis]

		source [file join $tool_dir lib flags.tcl]

		set build_system [detect_build_system]
		diag "build system: $build_system"

		source [file join $tool_dir lib build $build_system.tcl]

		# wipe build directory when rebuilding
		if {$rebuild && [file exists $build_dir]} {
			file delete -force $build_dir }

		prepare_abi_stubs [used_apis]
		prepare_ldso_support_stub [used_apis]

		source [file join $tool_dir lib quirks.tcl]

		# filter out non-existing include directories
		foreach dir $include_dirs {
			if {[file exists $dir]} {
				lappend existing_include_dirs $dir } }
		set include_dirs $existing_include_dirs

		# supplement 'cppflags' with include directories
		foreach dir $include_dirs {
			lappend cppflags "-I$dir" }

		# supplement 'cflags' with include directories too
		foreach dir $include_dirs {
			lappend cflags "-I$dir" }

		foreach api [used_apis] {
			lappend api_dirs [file join $depot_dir $api] }

		create_or_update_build_dir
	}


	proc artifact_file_list_from_list_file { list_file_path artifact_path } {
	
		set artifact_files { }
		set artifacts [read_file_content_as_list $list_file_path]
	
		foreach artifact $artifacts {
	
			# strip comments and empty lines
			regsub "#.*"   $artifact "" artifact
			regsub {^\s*$} $artifact "" artifact
			if {$artifact == ""} {
				continue }
	
			if {![regexp {^(.+:)?\s*(.+)$} $artifact dummy container selector]} {
				exit_with_error "invalid artifact declaration in $list_file_path:\n" \
				                "$artifact" }
	
			regsub {\s*:$} $container "" container
	
			# accept files and directories for archives, but only files for ROM modules
			set selected_types "f d"
			if {$container == ""} {
				set selected_types "f" }
	
			# determine list of selected files
			if {[regexp {/$} $selector dummy]} {
				# selector refers to the content of a directory
				regsub {/$} $selector "" selector
				set selected_dir [file join $artifact_path $selector]
				set files [glob -directory $selected_dir -nocomplain -types $selected_types *]
			} else {
				# selector refers to single file
				set files [list [file join $artifact_path $selector]]
			}
	
			# ROM module(s)
			if {$container == ""} {
	
				set missing_files { }
				set invalid_files { }
				foreach file $files {
					if {![file exists $file]} {
						append missing_files "\n $file" }
					if {[file isdirectory $file]} {
						append invalid_files "\n $file" }
				}
	
				if {[llength $missing_files] > 0} {
					exit_with_error "build artifact does not exist at $artifact_path:" \
					                "$missing_files" }
	
				if {[llength $invalid_files] > 0} {
					exit_with_error "build artifact is not a file: $invalid_files" }
	
				foreach file $files {
					lappend artifact_files $file
				}
			}
		}
	
		return $artifact_files
	}
	
	
	proc create_artifact_containers_from_list_file { list_file_path artifact_path tar_path } {
	
		set artifact_files { }
		set artifacts [read_file_content_as_list $list_file_path]
	
		foreach artifact $artifacts {
	
			# strip comments and empty lines
			regsub "#.*"   $artifact "" artifact
			regsub {^\s*$} $artifact "" artifact
			if {$artifact == ""} {
				continue }
	
			if {![regexp {^(.+:)?\s*(.+)$} $artifact dummy container selector]} {
				exit_with_error "invalid artifact declaration in $list_file_path:\n" \
				                "$artifact" }
	
			regsub {\s*:$} $container "" container
	
			# accept files and directories for archives, but only files for ROM modules
			set selected_types "f d"
			if {$container == ""} {
				set selected_types "f" }
	
			# determine list of selected files
			if {[regexp {/$} $selector dummy]} {
				# selector refers to the content of a directory
				regsub {/$} $selector "" selector
				set selected_dir [file join $artifact_path $selector]
				set files [glob -directory $selected_dir -nocomplain -types $selected_types *]
			} else {
				# selector refers to single file
				set files [list [file join $artifact_path $selector]]
			}
	
			# tar archive
			if {[regexp {^([^:]+\.tar)(/.*/)?} $container dummy archive_name archive_sub_dir]} {
	
				# strip leading slash from archive sub directory
				regsub {^/} $archive_sub_dir "" archive_sub_dir
	
				set archive_path [file join $tar_path "$archive_name"]
	
				diag "create $archive_path"
	
				foreach file $files {
					set cmd "tar rf $archive_path"
					lappend cmd -C [file dirname $file]
					lappend cmd --dereference
					lappend cmd --transform "s#^#$archive_sub_dir#"
					lappend cmd [file tail $file]
	
					if {[catch { exec -ignorestderr {*}$cmd }]} {
						exit_with_error "creation of tar artifact failed" }
				}
			}
		}
	}
	
	
	proc artifact_is_library { artifact } {
	
		set so_extension ".lib.so"
		set so_pattern "*$so_extension"
	
		return [string match $so_pattern $artifact];
	}
	
	
	proc extract_artifacts_from_build_dir { } {

		global config::project_dir config::build_dir config::bin_dir
		global config::dbg_dir config::debug
		variable library_artifacts { }
	
		set artifacts_file_path [file join $project_dir artifacts]
	
		# remove artifacts from last build
		if {[file exists $bin_dir]} {
			file delete -force $bin_dir }
		if {[file exists $dbg_dir]} {
			file delete -force $dbg_dir }
	
		if {![file exists $artifacts_file_path]} {
			return }
	
		file mkdir $bin_dir
		if { $debug } { file mkdir $dbg_dir }
	
		foreach file [artifact_file_list_from_list_file $artifacts_file_path $build_dir] {
			set symlink_path [file join $bin_dir [file tail $file]]
			file link $symlink_path [file fullnormalize $file]
	
			if {[artifact_is_library $file]} {
				lappend library_artifacts $file }
	
			extract_debug_info $file
			if { $debug && [file exists "$file.debug"]} {
				file link [file join $dbg_dir "[file tail $file].debug"] "$file.debug" }
	
			strip_binary $file
		}
	
		create_artifact_containers_from_list_file $artifacts_file_path $build_dir $bin_dir
	}
	
	
	proc check_abis { } {

		global tool_dir
		global config::arch config::project_dir config::cross_dev_prefix
		variable library_artifacts
	
		foreach library $library_artifacts {
	
			set so_extension ".lib.so"
			regsub $so_extension [file tail $library] "" symbols_file
			set symbols_file_name [file join $project_dir symbols $symbols_file]
	
			if {![file exists $symbols_file_name]} {
				exit_with_error "missing symbols file '$symbols_file'\n" \
				                "\n You can generate this file by running 'goa extract-abi-symbols'."
			}
	
			if {[catch { exec [file join $tool_dir abi check_abi] $library $symbols_file_name } msg]} {
				exit_with_error $msg
			}

			# sanity check for whether genode_rel.ld was used
			set expected_phdrs {LOAD r-x LOAD rw- DYNAMIC rw- EH_FRAME r--}
			set phdrs [split [exec_tool_chain objdump -p $library | grep -E "(off|filesz)"] \n]
			foreach {off filesz} $phdrs {exp_type exp_flags} $expected_phdrs {
				set type  [lindex $off 0]
				set flags [lindex $filesz end]
				if {$type != $exp_type || $flags != $exp_flags} {
					exit_with_error "program headers of '[file tail $library]' don't match their definition in genode_rel.ld\n" \
					                "\n Please check that the shared-object linker flags have been passed correctly."
				}
			}
		}
	}


	proc extract_api_artifacts { } {

		global config::project_dir config::build_dir config::api_dir
	
		set api_file_path [file join $project_dir api]
	
		# remove artifacts from last build
		if {[file exists $api_dir]} {
			file delete -force $api_dir }
	
		if {![file exists $api_file_path]} {
			return }
	
		file mkdir $api_dir
	
		foreach file [artifact_file_list_from_list_file $api_file_path $build_dir] {
			regsub "$build_dir/" $file "" link_src
			regsub "install/" $link_src "" link_src
			set dir [file dirname $link_src]
			set target_dir [file join $api_dir $dir]
			set link_target [file join $target_dir [file tail $file]]
	
			if {![file exists $target_dir]} {
				file mkdir $target_dir
			}
			file link $link_target $file
		}
	}
	
	
	proc extract_library_symbols { } {

		global tool_dir
		global config::build_dir config::project_dir
	
		set artifacts_file_path [file join $project_dir artifacts]
	
		if {![file exists $artifacts_file_path]} {
			return }
	
		set so_extension ".lib.so"
		set symbols_dir [file join $project_dir symbols]
	
		set libraries { }
		foreach artifact [artifact_file_list_from_list_file $artifacts_file_path $build_dir] {
	
			if {[artifact_is_library $artifact]} {
	
				# remove library extension
				regsub $so_extension $artifact "" symbols_file_name
	
				set symbols_file_name [file tail $symbols_file_name]
				set library_file_path [file join $build_dir $artifact]
				if {![file exists $library_file_path]} {
					exit_with_error "build artifact does not exist $artifact"}
	
				file mkdir $symbols_dir
				set symbols_file_path [file join $symbols_dir $symbols_file_name]
				if {[catch { exec [file join $tool_dir abi abi_symbols] $library_file_path > $symbols_file_path}]} {
					exit_with_error "unable to extract abi symbols"
				}
	
				lappend libraries $symbols_file_name
			}
		}
		return $libraries
	}

	proc extract-abi-symbols { } {

		set libraries [extract_library_symbols]
		if {[llength $libraries] > 0} {
	
			puts "The following library symbols file(s) were created:"
			foreach library $libraries {
				puts "  > `symbols/$library" }
	
			puts "Please review the symbols files(s) and add them to your repository."
		} else {
			exit_with_error "No libraries listed in the artifacts." }
	}
}
