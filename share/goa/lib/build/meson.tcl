
proc create_cross_file { dir } {
	global cross_dev_prefix

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
	# Setting the pkg-config command to '/bin/true'  will find all required
	# packages, make sure to have all required libraries in used_apis
	#
	puts $fh "pkg-config  = 'true'"

	puts $fh ""
	puts $fh "\[properties\]"
	puts $fh "needs_exec_wrapper = false"
	puts $fh ""
	puts $fh "\[host_machine\]"
	puts $fh "system     = 'freebsd'"
	puts $fh "cpu_family = 'x86_64'"
	puts $fh "cpu        = 'x86_64'"
	puts $fh "endian     = 'little'"
	close $fh

	return $cross_file
}


proc create_or_update_build_dir { } {
	global build_dir project_dir project_name
	global cross_dev_prefix
	global cppflags cflags cxxflags cc_cxx_opt_std
	global ldflags ldlibs_common ldlibs_exe
	global debug

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set source_dir [file join $project_dir src]

	set cmd { }
	lappend cmd meson
	lappend cmd "setup"

	# installation prefix
	lappend cmd "-Dprefix=[file join $build_dir install]"


	#
	# Options
	#

	# if debug -> enable assertion
	set b_ndebug  "true"
	if { $debug == 1 } { set b_ndebug "false" }
	lappend cmd "-Db_ndebug=$b_ndebug"

	#
	# Disable the -Wl,--as-needed ld flag, we always want all shared libaries to
	# appear in DT_NEEDED in the ELF file
	#
	lappend cmd "-Db_asneeded=false"


	#
	# c/c++/ld args
	#
	lappend cmd "-Dc_args=$cflags $cppflags"
	lappend cmd "-Dcpp_args=$cxxflags $cppflags"
	lappend cmd "-Dcpp_std=[lindex [split $cc_cxx_opt_std =/] 1]"
	lappend cmd "-Dc_link_args=$ldflags $ldlibs_common $ldlibs_exe"
	lappend cmd "-Dcpp_link_args=$ldflags $ldlibs_common $ldlibs_exe"

	#add project-specific arguments read from 'meson_args' file
	foreach arg [read_file_content_as_list [file join $project_dir meson_args]] {
		lappend cmd $arg }

	lappend cmd "--cross-file"
	lappend cmd [create_cross_file $build_dir]
	lappend cmd "--reconfigure"
	lappend cmd $build_dir
	lappend cmd $source_dir

	diag "create build directory via command: [pwd]" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via meson failed:\n" $msg }
}


proc build { } {
	global build_dir jobs project_name verbose

	set cmd [list ninja -C $build_dir "-j $jobs"]

	if { $verbose } {
		lappend cmd "--verbose"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "build via meson failed:\n" $msg }


	set cmd [list meson install -C $build_dir]
	if { $verbose == 0} {
		lappend cmd "--quiet"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:meson\] /" >@ stdout} msg]} {
		exit_with_error "install via meson failed:\n" $msg }
}
