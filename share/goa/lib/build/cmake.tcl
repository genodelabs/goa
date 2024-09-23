
proc create_or_update_build_dir { } {

	global tool_dir
	global cppflags cflags cxxflags ldflags ldflags_so ldlibs_common ldlibs_exe
	global ldlibs_so env cmake_quirk_args
	global config::build_dir config::project_dir config::abi_dir
	global config::cross_dev_prefix config::include_dirs config::project_name
	global api_dirs

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set orig_pwd [pwd]
	cd $build_dir

	set     cmd [goa::sandboxed_build_command]
	lappend cmd --setenv LDFLAGS "$ldflags $ldlibs_common $ldlibs_exe"

	lappend cmd cmake
	lappend cmd "-DCMAKE_IGNORE_PREFIX_PATH='/;/usr'"
	lappend cmd "-DCMAKE_MODULE_PATH='[join ${api_dirs} ";"];[file join $tool_dir cmake Modules]'"
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

	diag "create build directory via cmake"

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via cmake failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {
	global verbose tool_dir
	global ldflags ldlibs_common ldlibs_exe
	global config::build_dir config::jobs config::project_name

	set     cmd [goa::sandboxed_build_command]
	lappend cmd --setenv LDFLAGS "$ldflags $ldlibs_common $ldlibs_exe"
	lappend cmd make -C $build_dir "-j$jobs"

	if {$verbose == 0} {
		lappend cmd "-s"
	} else {
		lappend cmd "VERBOSE=1"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "build via cmake failed:\n" $msg }

	# return if 'install' target does not exist
	if {[exec_status [list {*}$cmd -q install]] == 2} {
		return }

	# at this point, we know that the 'install' target exists
	lappend cmd install
	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cmake\] /" >@ stdout} msg]} {
		exit_with_error "install via cmake failed:\n" $msg }
}
