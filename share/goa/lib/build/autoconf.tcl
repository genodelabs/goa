
proc create_or_update_build_dir { } {

	mirror_source_dir_to_build_dir

	global build_dir cross_dev_prefix project_name project_dir api_dirs
	global cppflags cflags cxxflags ldflags ldlibs_common ldlibs_exe ldlibs_so

	# invoke configure script only once
	if {[file exists [file join $build_dir config.status]]} {
		return }

	set orig_pwd [pwd]

	#
	# If the configure script doesn't exist yet, it has to be
	# generated first via the configure.ac file using autoreconf.
	#
	if {[expr ![file exists [file join src configure]]]} {

		set cmd { }

		lappend cmd "autoreconf"
		lappend cmd "--install"

		diag "create build system via command:" {*}$cmd

		cd $build_dir
		if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:autoconf\] /" >@ stdout} msg]} {
			exit_with_error "build-system creation via autoconf failed:\n" $msg
		}
		cd $orig_pwd
	}

	set cmd { }

	lappend cmd "./configure"
	lappend cmd "--prefix" "/"
	lappend cmd "--host" x86_64-pc-elf
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CXXFLAGS=$cxxflags"
	lappend cmd "LDFLAGS=$ldflags $ldlibs_common"
	lappend cmd "LDLIBS=$ldlibs_common $ldlibs_exe"
	lappend cmd "LDLIBS_SHARED=$ldlibs_common $ldlibs_so"
	lappend cmd "LIBS=$ldlibs_common $ldlibs_exe"
	lappend cmd "CXX=${cross_dev_prefix}g++"
	lappend cmd "CC=${cross_dev_prefix}gcc"
	lappend cmd "STRIP=${cross_dev_prefix}strip"
	lappend cmd "RANLIB=${cross_dev_prefix}ranlib"
	lappend cmd "AR=${cross_dev_prefix}ar"
	lappend cmd "AS=${cross_dev_prefix}as"
	lappend cmd "PKG_CONFIG_LIBDIR=''"
	lappend cmd "PKG_CONFIG_PATH=[join ${api_dirs} ":"]"

	#
	# Some autoconf projects (e.g. OpenSC) unconditionally do checks
	# on the C/C++ preprocessors and therefore need these variables.
	#
	lappend cmd "CPP=${cross_dev_prefix}cpp"
	lappend cmd "CXXCPP=${cross_dev_prefix}cpp"

	# add project-specific arguments read from 'configure_args' file
	foreach arg [read_file_content_as_list [file join $project_dir configure_args]] {
		lappend cmd $arg }

	diag "create build directory via command:" {*}$cmd

	cd $build_dir

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:autoconf\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via autoconf failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {

	global build_dir verbose project_name jobs project_dir ldlibs_common ldlibs_exe ldlibs_so

	set cmd { }

	# pass variables that are not fully handled by configure scripts
	lappend cmd make -C $build_dir
	lappend cmd "LDLIBS=$ldlibs_common $ldlibs_exe"
	lappend cmd "LDLIBS_SHARED=$ldlibs_common $ldlibs_so"
	lappend cmd "DESTDIR=[file join $build_dir install]"
	lappend cmd "-j$jobs"

	#
	# Autoconf adds consideration of the variable 'V' to generated Makefiles
	# in order to control make verbosity. There are only two values: '0'
	# means less verbosity and '1' more verbosity.
	#
	if {$verbose == 1} {
		lappend cmd "V=1"
	} else {
		lappend cmd "-s"
		lappend cmd "V=0"
	}

	# add project-specific arguments read from 'make_args' file
	foreach arg [read_file_content_as_list [file join $project_dir make_args]] {
		lappend cmd $arg }

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
		exit_with_error "install via make failed" }
}
