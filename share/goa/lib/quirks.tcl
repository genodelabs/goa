if {[using_api libc]} {

	set libc_include_dir [file join [api_archive_dir libc] include]

	lappend include_dirs [file join $libc_include_dir libc]
	lappend include_dirs [file join $libc_include_dir libc-genode]

	if {$arch == "x86_64"} {
		lappend include_dirs [file join $libc_include_dir spec x86    libc]
		lappend include_dirs [file join $libc_include_dir spec x86_64 libc]
	}
	if {$arch == "arm_v8a"} {
		lappend include_dirs [file join $libc_include_dir spec arm_64 libc]
	}

	# trigger include of 'sys/signal.h' to make NSIG visible
	lappend cppflags "-D__BSD_VISIBLE"
	# prevent gcc headers from defining __size_t
	lappend cppflags "-D__FreeBSD__=8"
}

if {[using_api stdcxx]} {

	set stdcxx_include_dir [file join [api_archive_dir stdcxx] include]

	lappend include_dirs [file join $stdcxx_include_dir stdcxx]
	lappend include_dirs [file join $stdcxx_include_dir stdcxx std]
	lappend include_dirs [file join $stdcxx_include_dir stdcxx c_global]

	if {$arch == "x86_64"} {
		lappend include_dirs [file join $stdcxx_include_dir spec x86_64 stdcxx]
	}
	if {$arch == "arm_v8a"} {
		lappend include_dirs [file join $stdcxx_include_dir spec arm_64 stdcxx]
	}
}

if {[using_api sdl]} {

	# CMake's detection of libSDL expects the library named uppercase
	set symlink_name [file join $abi_dir SDL.lib.so]
	if {![file exists $symlink_name]} {
		file link -symbolic $symlink_name "sdl.lib.so" }

	# search for headers in the inlude/SDL sub directory
	set sdl_include_dir [file join [api_archive_dir sdl] include SDL]
	lappend include_dirs $sdl_include_dir

	# bring CMake on the right track to find the headers and library
	lappend cmake_quirk_args "-DSDL_INCLUDE_DIR=$sdl_include_dir"
	lappend cmake_quirk_args "-DCMAKE_SYSTEM_LIBRARY_PATH='$abi_dir'"
	lappend cmake_quirk_args "-DSDL_LIBRARY:STRING=':sdl.lib.so'"
}

if {[using_api curl]} {

	if {$arch == "x86_64"} {
		lappend include_dirs [file join [api_archive_dir curl] src lib curl spec 64bit curl]
	}
}

if {[using_api posix]} {

	#
	# Genode's fork mechanism relies on a specific order of the linked
	# shared libraries libc, vfs, libm, and posix. Since the order of apis
	# listed in the 'used_apis' file can be arbitrary, we ensure the
	# link oder by reordering 'ldlibs_exe'.
	#

	# remove critical entries
	foreach lib [list libc libm posix] {
		set idx [lsearch -exact $ldlibs_exe "-l:$lib.lib.so"]
		if {$idx != -1} { set ldlibs_exe [lreplace $ldlibs_exe $idx $idx] }
	}

	# prepend known-good link order of the critical libaries
    set ldlibs_exe [linsert $ldlibs_exe 0 "-l:libc.lib.so" "-l:libm.lib.so" "-l:posix.lib.so"]
}

if {[using_api blit]} {

	set blit_dir [file join [api_archive_dir blit] src lib blit]

	if {$arch == "x86_64"} {
		lappend include_dirs [file join $blit_dir spec x86]
		lappend include_dirs [file join $blit_dir spec x86_64]
	}
	if {$arch == "arm_v8a"} {
		lappend include_dirs [file join $blit_dir spec arm_64]
	}

	lappend lib_src [file join $blit_dir blit.cc]
}
