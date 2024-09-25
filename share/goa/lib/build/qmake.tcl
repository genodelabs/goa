proc _qmake_platform { } {
	global config::arch

	if {$arch == "x86_64"} {
		set qmake_platform "genode-x86_64-g++"
	} elseif {$arch == "arm_v8a"} {
		set qmake_platform "genode-aarch64-g++"
	} else {
		exit_with_error "build via qmake failed: unsupported architecture: $arch\n"
	}

	return $qmake_platform
}


proc _qt_version { } {
	if { [regexp qt5_base [used_apis]] } {
		return "qt5"
	} elseif { [regexp qt6_base [used_apis]] } {
		return "qt6"
	}

	exit_with_error "build via qmake failed: unable to detect Qt version\n" \
	                "\n Please add qt5_base or qt6_base to your 'used_apis' file."
}


proc _qmake_build_cmd { qt_version qmake_platform } {
	global cppflags cxxflags ldflags ldflags_so ldlibs_common
	global ldlibs_exe ldlibs_so
	global config::build_dir
	global config::cross_dev_prefix

	set qmake_cflags     "$cppflags $cxxflags "
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

	set     cmd [sandboxed_build_command]
	lappend cmd --setenv GENODE_QMAKE_CC           "${cross_dev_prefix}gcc"
	lappend cmd --setenv GENODE_QMAKE_CXX          "${cross_dev_prefix}g++"
	lappend cmd --setenv GENODE_QMAKE_LINK         "${cross_dev_prefix}g++"
	lappend cmd --setenv GENODE_QMAKE_AR           "${cross_dev_prefix}ar"
	lappend cmd --setenv GENODE_QMAKE_OBJCOPY      "${cross_dev_prefix}objcopy"
	lappend cmd --setenv GENODE_QMAKE_NM           "${cross_dev_prefix}nm"
	lappend cmd --setenv GENODE_QMAKE_STRIP        "${cross_dev_prefix}strip"
	lappend cmd --setenv GENODE_QMAKE_CFLAGS       "$qmake_cflags"
	lappend cmd --setenv GENODE_QMAKE_LFLAGS_APP   "$ldflags $ldlibs_common $ldlibs_exe $qmake_ldlibs"
	lappend cmd --setenv GENODE_QMAKE_LFLAGS_SHLIB "$ldflags_so $ldlibs_common $ldlibs_so $qmake_ldlibs"

	#
	# libgcc must appear on the command line after all other libs
	# (including those added by qmake) and using the QMAKE_LIBS
	# variable achieves this, fortunately
	#
	lappend cmd --setenv GENODE_QMAKE_LIBS "-lgcc"

	return $cmd
}


proc create_or_update_build_dir { } {

	global cppflags cxxflags ldflags ldflags_so ldlibs_common
	global ldlibs_exe ldlibs_so
	global config::build_dir config::project_dir config::abi_dir
	global config::cross_dev_prefix config::project_name
	global config::toolchain_version

	set qmake_platform [_qmake_platform]
	set qt_version     [_qt_version]
	if { $qt_version == "qt6" } {
		set qt_tool_dir "/usr/local/genode/tool/$toolchain_version/qt6"
	} else {
		set qt_tool_dir "/usr/local/genode/tool/$toolchain_version"
	}

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set orig_pwd [pwd]
	cd $build_dir

	file delete -force qmake_root
	file mkdir qmake_root

	set qt_api ${qt_version}_base

	# $qt5_tool_dir might only exist in sandbox environment, hence use ln
	exec ln -sf $qt_tool_dir/bin qmake_root/bin

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

	cd $orig_pwd

	set qt_conf "qmake_root/mkspecs/$qmake_platform/qt.conf"
	set     cmd [_qmake_build_cmd $qt_version $qmake_platform]
	lappend cmd [file join $qt_tool_dir/bin qmake] -qtconf $qt_conf [file join $project_dir src]

	diag "create build directory via qmake"

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:qmake\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via qmake failed:\n" $msg }
}


proc build { } {
	global verbose
	global config::build_dir config::jobs config::project_name

	set     cmd [_qmake_build_cmd [_qt_version] [_qmake_platform]]
	lappend cmd make -C $build_dir "-j$jobs"

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
