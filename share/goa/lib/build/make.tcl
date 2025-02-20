proc _make_cmd { } {
	global build_dir cross_dev_prefix verbose jobs project_dir
	global cppflags cflags cxxflags ldflags ldlibs_common ldlibs_exe lib_src
	global ldflags_so ldlibs_so

	set cmd { }

	lappend cmd make -C $build_dir
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CXXFLAGS=$cxxflags"
	lappend cmd "LDFLAGS=$ldflags"
	lappend cmd "LDLIBS=$ldlibs_common $ldlibs_exe"
	lappend cmd "CXX=$cross_dev_prefix\g++"
	lappend cmd "CC=$cross_dev_prefix\gcc"
	lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
	lappend cmd "LIB_SRC=$lib_src"
	lappend cmd "-j$jobs"
	lappend cmd "MAKE_SHARED_LINKER_FLAGS=\"$ldflags_so $ldlibs_common $ldlibs_so\""

	if {$verbose == 0} {
		lappend cmd "-s" }

	# add project-specific arguments read from 'make_args' file
	foreach arg [read_file_content_as_list [file join $project_dir make_args]] {
		lappend cmd $arg }

	return $cmd
}


proc create_or_update_build_dir { } {
	global build_dir

	# compare make command and clear directory if anything changed
	set signature_file [file join $build_dir ".goa_make_command"]

	set previous_cmd { }
	set cmd [_make_cmd]

	# read previous command from file
	if {[file exists $signature_file]} {
		set fd [open $signature_file]
		set previous_cmd [string trim [read $fd]]
		close $fd
	}

	if {"$previous_cmd" != "$cmd"} {
		file delete -force $build_dir }

	mirror_source_dir_to_build_dir

	# write build command to file
	set fd [open $signature_file w]
	puts $fd [join $cmd { }]
	close $fd
}


proc build { } {
	global project_name

	set cmd [_make_cmd]

	# skip make (and make install) if there is nothing to be made
	if {[exec_status [list {*}$cmd -q]] == 0} {
		diag "everything is up to date"
		return
	}

	diag "build via command" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:make\] /" >@ stdout}]} {
		exit_with_error "build via make failed" }

	# return if 'install' target does not exist
	if {[exec_status [list {*}$cmd -q install]] == 2} {
		return }

	# at this point, we know that the 'install' target exists
	lappend cmd install
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:make\] /" >@ stdout}]} {
		exit_with_error "install via make failed"  }
}
