#
# Meson specific implementation
#

proc api_status { } {
	global config::build_dir

	set pkg_config_log [file join $build_dir "pkg-config.log"]
	set module_status  [read_file_content_as_list $pkg_config_log]
	set module_status  [lsort -unique $module_status]

	if {[llength $module_status] == 0} { return }

	log "pkg-config status:"
	foreach module $module_status {
		set status [split $module ":"]
		set found [expr [lindex $status 1] == 1 ? "YES" : "NO" ]
		log "\t[lindex $status 0] found: $found"
	}
}


proc create_cross_file { dir } {
	global tool_dir
	global config::arch config::cross_dev_prefix

	set target_machine x86_64
	if {$arch == "arm_v8a"} { set target_machine aarch64 }

	set cross_file [file join $dir meson-cross-genode]

	set fh [open $cross_file "WRONLY CREAT TRUNC"]
	puts $fh "# Genode tool chain for cross compilation (--cross-file)"
	puts $fh "# Automatically generated file."
	puts $fh ""
	puts $fh "\[binaries\]"
	puts $fh "c      = '${cross_dev_prefix}gcc'"
	puts $fh "cpp    = '${cross_dev_prefix}g++'"
	puts $fh "ar     = '${cross_dev_prefix}ar'"
	puts $fh "strip  = '${cross_dev_prefix}strip'"

	#
	# Custom pkg-config command that checks if required libraries are present in
	# abi_dir
	#
	puts $fh "pkg-config = '$tool_dir/lib/pkg-config.tcl'"

	puts $fh ""
	puts $fh "\[properties\]"
	puts $fh "needs_exec_wrapper = false"
	puts $fh "pkg_config_libdir  = '$dir'"
	puts $fh ""
	puts $fh "\[host_machine\]"
	puts $fh "system     = 'freebsd'"
	puts $fh "cpu_family = 'x86_64'"
	puts $fh "cpu        = 'x86_64'"
	puts $fh "endian     = 'little'"
	puts $fh ""
	puts $fh "\[target_machine\]"
	puts $fh "system     = 'freebsd'"
	puts $fh "cpu_family = '$target_machine'"
	puts $fh "cpu        = '$target_machine'"
	puts $fh "endian     = 'little'"
	puts $fh ""
	close $fh

	return $cross_file
}


proc create_or_update_build_dir { } {
	global cppflags cflags cxxflags
	global ldflags ldlibs_exe ldlibs_common
	global config::build_dir config::project_dir config::abi_dir config::project_name
	global config::cross_dev_prefix config::cc_cxx_opt_std config::debug

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	# create/empty pkg-config.log
	set pkg_config_log [file join $build_dir "pkg-config.log"]
	set fh [open $pkg_config_log "WRONLY CREAT TRUNC"]
	close $fh

	# create link to abi to be processed by 'pkg-config.tcl'
	set link_abi [file join $build_dir abi]
	if {[expr ![file exists $link_abi]]} {
		file link -symbolic $link_abi $abi_dir
	}

	set source_dir [file join $project_dir src]

	set     cmd [sandboxed_build_command]
	lappend cmd meson
	lappend cmd "setup"

	# installation prefix
	lappend cmd "-Dprefix=[file join $build_dir install]"


	#
	# Options
	#

	# if debug -> enable assertion
	set b_ndebug  "true"
	if { $debug == 1 } {
		set b_ndebug "false"
	} else {
		lappend cmd "--strip"
	}
	lappend cmd "-Db_ndebug=$b_ndebug"

	#
	# Disable the -Wl,--as-needed ld flag, we always want all shared libaries to
	# appear in DT_NEEDED in the ELF file
	#
	lappend cmd "-Db_asneeded=false"


	#
	# c/c++ args
	#
	lappend cmd "-Dc_args=$cflags $cppflags"
	lappend cmd "-Dcpp_args=$cxxflags $cppflags"
	lappend cmd "-Dcpp_std=[lindex [split $cc_cxx_opt_std =/] 1]"

	#
	# Used for feature testing compiles, since these are usally 'main' test builds
	# use executable version
	#
	lappend cmd "-Dc_link_args=$ldflags $ldlibs_exe $ldlibs_common"
	lappend cmd "-Dcpp_link_args=$ldflags $ldlibs_exe $ldlibs_common"


	# add project-specific arguments read from 'meson_args' file
	foreach arg [read_file_content_as_list [file join $project_dir meson_args]] {
		lappend cmd $arg }

	lappend cmd "--cross-file"
	lappend cmd [create_cross_file $build_dir]
	lappend cmd "--reconfigure"
	lappend cmd $build_dir
	lappend cmd $source_dir

	diag "create build directory via meson"

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via meson failed:\n" $msg }

	api_status
}


proc retrieve_build_targets { json shared } {
	set targets { }

	foreach item $json {
		dict with item {
			# skip targets that will not be installed
			if {!$installed} { continue }

			if {$shared  && $type == "shared library"} { lappend targets $name }
			if {!$shared && $type != "shared library"} { lappend targets $name }
		}
	}

	return $targets
}


proc retrieve_rpath_link { } {
	global config::project_dir

	set rpath_link { }
	foreach arg [read_file_content_as_list [file join $project_dir rpath_link]] {

		# escape $ at beginning of line with \ (e.g., for $ORIGIN)
		if {[regexp {^\$} $arg]} { regsub {^\$} $arg "\\$" arg }
		lappend rpath_link $arg
	}

	return $rpath_link
}


proc build_targets { targets link_args shared } {
	global verbose
	global config::build_dir config::jobs
	global config::project_dir config::project_name
	global ldflags ldflags_so ldlibs_common ldlibs_exe ldlibs_so

	# configure build directory for executable or shared library build
	set     cmd [sandboxed_build_command]
	lappend cmd meson configure

	# put ldlibs_common last in order to have -lgcc at the end of command line
	if {$shared} {

		#
		# Filter out -Wl,-shared because it will be added by Meson and stands in the
		# way of Meson's build tests because tests will succeed linking with
		# undefined symbols
		#
		set libs_so ""
		regsub {\-Wl,\-shared} $ldlibs_so "" libs_so

		lappend cmd "\"-Dc_link_args=$ldflags_so $libs_so $link_args $ldlibs_common\""
		lappend cmd "\"-Dcpp_link_args=$ldflags_so $libs_so $link_args $ldlibs_common\""
	} else {
		lappend cmd "\"-Dc_link_args=$ldflags $ldlibs_exe $link_args $ldlibs_common\""
		lappend cmd "\"-Dcpp_link_args=$ldflags $ldlibs_exe $link_args $ldlibs_common\""
	}

	lappend cmd $build_dir

	diag "reconfigure: shared-library build: $shared"
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "configure via meson failed:\n" $msg }

	diag "commit: configuration"
	exec -ignorestderr {*}[sandboxed_build_command] meson setup --reconfigure $build_dir $project_dir/src

	# Meson uses gcc/g++ -shared to create shared libraries, this does not work
	# with our tool chain on arm_v8a and produces an executable instead of a
	# shared library. Replace all occurences of -shared by -Wl,-shared in the
	# resulting Ninja build file because I don't see another way at the moment.
	#
	# TODO: find out why -shared doesn't work with Genode's aarch64 toolchain
	diag "hack: patching build.ninja with -Wl,-shared"
	exec sed -i "s/ -shared/ -Wl,-shared/g" $build_dir/build.ninja

	# build
	diag "build:"
	set     cmd [sandboxed_build_command]
	lappend cmd meson compile -C $build_dir -j $jobs {*}$targets

	if {$verbose} { lappend cmd "--verbose" }

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "build via meson failed:\n" $msg }
}


proc build { } {
	global verbose tool_dir
	global config::build_dir config::project_name

	set link_args ""
	set rpath_link [retrieve_rpath_link]
	if {[llength $rpath_link] > 0} {
		set link_args -Wl,-rpath-link=[join $rpath_link :]
	}

	# json parser from tcllib
	source [file join $tool_dir lib tcllib json.tcl]

	# retrieve build targets (1 -> enforce silent since we read stdout)
	diag "retrieving build information using meson introspect ..."
	set     json_cmd [sandboxed_build_command 1]
	lappend json_cmd meson introspect -i --targets $build_dir

	set json      [exec -ignorestderr {*}$json_cmd]
	set json_dict [::json::json2dict $json]

	# configure and build executables
	set targets [retrieve_build_targets $json_dict false]
	diag "building [llength $targets] executables: $targets"

	if {[llength $targets] > 0} { build_targets $targets $link_args false }

	# configure and build shared libraries
	set targets [retrieve_build_targets $json_dict true]
	diag "building [llength $targets] shared libraries: $targets"

	if {[llength $targets] > 0} { build_targets $targets $link_args true }

	# install
	set     cmd [sandboxed_build_command]
	lappend cmd meson install --no-rebuild -C $build_dir
	if { $verbose == 0} {
		lappend cmd "--quiet"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "install via meson failed:\n" $msg }
}
