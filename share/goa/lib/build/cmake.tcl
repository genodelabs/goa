
proc create_or_update_build_dir { } {

	global build_dir project_dir abi_dir tool_dir cross_dev_prefix include_dirs
	global cppflags cflags cxxflags ldflags ldflags_so ldlibs_common ldlibs_exe ldlibs_so project_name
	global cmake_quirk_args
	global env

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set orig_pwd [pwd]
	cd $build_dir

	set ::env(LDFLAGS) "$ldflags $ldlibs_common $ldlibs_exe"

	set cmd { }
	lappend cmd cmake
	lappend cmd "-DCMAKE_MODULE_PATH=[file join $tool_dir cmake Modules]"
	lappend cmd "-DCMAKE_SYSTEM_NAME=Genode"
	lappend cmd "-DCMAKE_C_COMPILER=${cross_dev_prefix}gcc"
	lappend cmd "-DCMAKE_CXX_COMPILER=${cross_dev_prefix}g++"
	lappend cmd "-DCMAKE_C_FLAGS='$cflags $cppflags'"
	lappend cmd "-DCMAKE_CXX_FLAGS='$cxxflags $cppflags'"
	lappend cmd "-DCMAKE_EXE_LINKER_FLAGS='$ldflags $ldlibs_common $ldlibs_exe'"
	lappend cmd "-DCMAKE_SHARED_LINKER_FLAGS='$ldflags_so $ldlibs_common $ldlibs_so'"
	lappend cmd "-DCMAKE_MODULE_LINKER_FLAGS='$ldflags_so $ldlibs_common $ldlibs_so'"
	lappend cmd "-DCMAKE_INSTALL_PREFIX:PATH=[file join $build_dir install]"
	lappend cmd "-DCMAKE_SYSTEM_LIBRARY_PATH='$abi_dir'"

	if {[info exists cmake_quirk_args]} {
		foreach arg $cmake_quirk_args {
			lappend cmd $arg } }

	# add project-specific arguments read from 'cmake_args' file
	foreach arg [read_file_content_as_list [file join $project_dir cmake_args]] {
		lappend cmd $arg }

	lappend cmd [file join $project_dir src]

	diag "create build directory via command:" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via cmake failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {
	global build_dir jobs project_name verbose

	set cmd [list make -C $build_dir "-j$jobs"]

	if {$verbose == 0} {
		lappend cmd "-s"
	} else {
		lappend cmd "VERBOSE=1"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build via cmake failed:\n" $msg }

	# test whether 'install' target exists
	set test_cmd [list {*}$cmd -q install]
	if {[catch {exec {*}$test_cmd} msg options]} {
		set details [dict get $options -errorcode]
		if {[lindex $details 0] eq "CHILDSTATUS"} {
			if {[lindex $details 2] == 2} { return } }
	}

	# at this point, we know that the 'install' target exists
	lappend cmd install
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "install via cmake failed:\n" $msg }
}
