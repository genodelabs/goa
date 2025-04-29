
proc create_or_update_build_dir { } {

	global cppflags cxxflags ldflags ldflags_so ldlibs_common
	global ldlibs_exe ldlibs_so env
	global config::build_dir config::project_dir config::abi_dir
	global config::cross_dev_prefix config::arch config::project_name

	if { [regexp qt5_base [used_apis]] } {
		set qt_version qt5
		set qt_tool_dir "/usr/local/genode/tool/23.05"
	} elseif { [regexp qt6_base [used_apis]] } {
		set qt_version qt6
		set qt_tool_dir "/usr/local/genode/tool/23.05/qt6"
	} else {
		exit_with_error "build via qmake failed: unable to detect Qt version\n" \
		                "\n Please add qt5_base or qt6_base to your 'used_apis' file."
	}

	if {$arch == "x86_64"} {
		set qmake_platform "genode-x86_64-g++"
	} elseif {$arch == "arm_v8a"} {
		set qmake_platform "genode-aarch64-g++"
	} else {
		exit_with_error "build via qmake failed: unsupported architecture: $arch\n"
	}

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set orig_pwd [pwd]
	cd $build_dir

	file delete -force qmake_root
	file mkdir qmake_root

	set qt_api ${qt_version}_base

	file link -symbolic qmake_root/bin $qt_tool_dir/bin
	file link -symbolic qmake_root/include [file join [api_archive_dir $qt_api] include]
	file link -symbolic qmake_root/lib $abi_dir
	file link -symbolic qmake_root/libexec $qt_tool_dir/libexec

	file mkdir qmake_root/mkspecs
	file link -symbolic qmake_root/mkspecs/common            [file join [api_archive_dir $qt_api] mkspecs common]
	file link -symbolic qmake_root/mkspecs/features          [file join [api_archive_dir $qt_api] mkspecs features]
	file link -symbolic qmake_root/mkspecs/$qmake_platform   [file join [api_archive_dir $qt_api] mkspecs $qmake_platform]
	file link -symbolic qmake_root/mkspecs/linux-g++         [file join [api_archive_dir $qt_api] mkspecs linux-g++]
	file link -symbolic qmake_root/mkspecs/modules           [file join [api_archive_dir $qt_api] mkspecs modules]
	file link -symbolic qmake_root/mkspecs/qconfig.pri       $qmake_platform/qconfig.pri
	file link -symbolic qmake_root/mkspecs/qmodule.pri       $qmake_platform/qmodule.pri

	set qmake_cflags    "$cppflags $cxxflags "
	append qmake_cflags "-D__GENODE__ -D__FreeBSD__=12 "

	if { $qt_version == "qt5" } {
		append qmake_cflags "-I$build_dir/qmake_root/include/QtCore/spec/$qmake_platform"
	} else {
		append qmake_cflags "-I$build_dir/qmake_root/mkspecs/$qmake_platform"
	}

	set qmake_ldlibs { }
	lappend qmake_ldlibs -l:libc.lib.so
	lappend qmake_ldlibs -l:libm.lib.so
	lappend qmake_ldlibs -l:stdcxx.lib.so
	lappend qmake_ldlibs -l:${qt_version}_component.lib.so

	set ::env(GENODE_QMAKE_CC)           "${cross_dev_prefix}gcc"
	set ::env(GENODE_QMAKE_CXX)          "${cross_dev_prefix}g++"
	set ::env(GENODE_QMAKE_LINK)         "${cross_dev_prefix}g++"
	set ::env(GENODE_QMAKE_AR)           "${cross_dev_prefix}ar"
	set ::env(GENODE_QMAKE_OBJCOPY)      "${cross_dev_prefix}objcopy"
	set ::env(GENODE_QMAKE_NM)           "${cross_dev_prefix}nm"
	set ::env(GENODE_QMAKE_STRIP)        "${cross_dev_prefix}strip"
	set ::env(GENODE_QMAKE_CFLAGS)       "$qmake_cflags"
	set ::env(GENODE_QMAKE_LFLAGS_APP)   "$ldflags $ldlibs_common $ldlibs_exe $qmake_ldlibs"
	set ::env(GENODE_QMAKE_LFLAGS_SHLIB) "$ldflags_so $ldlibs_common $ldlibs_so $qmake_ldlibs"

	#
	# libgcc must appear on the command line after all other libs
	# (including those added by qmake) and using the QMAKE_LIBS
	# variable achieves this, fortunately
	#
	set ::env(GENODE_QMAKE_LIBS) "-lgcc"

	set qt_conf "qmake_root/mkspecs/$qmake_platform/qt.conf"
	set cmd [list [file join $qt_tool_dir/bin qmake] -qtconf $qt_conf [file join $project_dir src]]

	diag "create build directory via command:" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:qmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via qmake failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {
	global verbose
	global config::build_dir config::jobs config::project_name

	set cmd [list make -C $build_dir "-j$jobs"]

	if {$verbose == 0} {
		lappend cmd "-s"
	} else {
		lappend cmd "VERBOSE=1"
	}

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:qmake\] /" >@ stdout} msg]} {
		exit_with_error "build via qmake failed:\n" $msg }

	lappend cmd "install"
	catch {exec -ignorestderr {*}$cmd}
}
