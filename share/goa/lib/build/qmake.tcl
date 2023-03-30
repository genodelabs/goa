
proc create_or_update_build_dir { } {

	global build_dir project_dir abi_dir cross_dev_prefix arch
	global cppflags cxxflags ldflags ldlibs_exe project_name
	global env

	set qt5_tool_dir "/usr/local/genode/qt5/20.08/bin"

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

	file link -symbolic qmake_root/bin $qt5_tool_dir
	file link -symbolic qmake_root/include [file join [api_archive_dir qt5] include]
	file link -symbolic qmake_root/lib $abi_dir

	file mkdir qmake_root/mkspecs
	file link -symbolic qmake_root/mkspecs/common            [file join [api_archive_dir qt5] mkspecs common]
	file link -symbolic qmake_root/mkspecs/features          [file join [api_archive_dir qt5] mkspecs features]
	file link -symbolic qmake_root/mkspecs/$qmake_platform   [file join [api_archive_dir qt5] mkspecs $qmake_platform]
	file link -symbolic qmake_root/mkspecs/linux-g++         [file join [api_archive_dir qt5] mkspecs linux-g++]
	file link -symbolic qmake_root/mkspecs/modules           [file join [api_archive_dir qt5] mkspecs modules]
	file link -symbolic qmake_root/mkspecs/qconfig.pri       $qmake_platform/qconfig.pri
	file link -symbolic qmake_root/mkspecs/qmodule.pri       $qmake_platform/qmodule.pri

	set qmake_cflags     "$cppflags $cxxflags "
	append qmake_cflags "-D__GENODE__ -D__FreeBSD__=12 "
	append qmake_cflags "-I$build_dir/qmake_root/include/QtCore/spec/$qmake_platform"

	set qmake_ldlibs { }
	lappend qmake_ldlibs -nostdlib
	lappend qmake_ldlibs -L$abi_dir
	lappend qmake_ldlibs -l:libc.lib.so
	lappend qmake_ldlibs -l:libm.lib.so
	lappend qmake_ldlibs -l:stdcxx.lib.so
	lappend qmake_ldlibs -l:qt5_component.lib.so
	lappend qmake_ldlibs -l:qt5_component.lib.so

	if {$arch == "x86_64"} {
		lappend qmake_ldlibs [file normalize [exec $cross_dev_prefix\gcc -m64 -print-libgcc-file-name]]
	} else {
		lappend qmake_ldlibs [file normalize [exec $cross_dev_prefix\gcc -print-libgcc-file-name]]
	}

	set ::env(GENODE_QMAKE_CC)         "${cross_dev_prefix}gcc"
	set ::env(GENODE_QMAKE_CXX)        "${cross_dev_prefix}g++"
	set ::env(GENODE_QMAKE_LINK)       "${cross_dev_prefix}g++"
	set ::env(GENODE_QMAKE_AR)         "${cross_dev_prefix}ar"
	set ::env(GENODE_QMAKE_OBJCOPY)    "${cross_dev_prefix}objcopy"
	set ::env(GENODE_QMAKE_NM)         "${cross_dev_prefix}nm"
	set ::env(GENODE_QMAKE_STRIP)      "${cross_dev_prefix}strip"
	set ::env(GENODE_QMAKE_CFLAGS)     "$qmake_cflags"
	set ::env(GENODE_QMAKE_LFLAGS_APP) "-nostdlib $ldflags $ldlibs_exe $qmake_ldlibs"

	set qt_conf "qmake_root/mkspecs/$qmake_platform/qt.conf"
	set cmd [list [file join $qt5_tool_dir qmake] -qtconf $qt_conf [file join $project_dir src]]

	diag "create build directory via command:" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:qmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via qmake failed:\n" $msg }

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

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:qmake\] /" >@ stdout} msg]} {
		exit_with_error "build via qmake failed:\n" $msg }

	lappend cmd "install"
	catch {exec -ignorestderr {*}$cmd}
}
