if {[using_api libc]} {

	set libc_include_dir [file join [api_archive_dir libc] include]

	lappend include_dirs [file join $libc_include_dir libc]
	lappend include_dirs [file join $libc_include_dir libc-genode]

	if {$arch == "x86_64"} {
		lappend include_dirs [file join $libc_include_dir spec x86    libc]
		lappend include_dirs [file join $libc_include_dir spec x86_64 libc]
	}
}

if {[using_api stdcxx]} {

	set stdcxx_include_dir [file join [api_archive_dir stdcxx] include]

	lappend include_dirs [file join $stdcxx_include_dir stdcxx]
	lappend include_dirs [file join $stdcxx_include_dir stdcxx std]
	lappend include_dirs [file join $stdcxx_include_dir stdcxx c_global]
}
