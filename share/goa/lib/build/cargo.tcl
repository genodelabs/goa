
proc create_or_update_build_dir { } { mirror_source_dir_to_build_dir }

proc generate_static_stubs { libs } {
	global tool_dir abi_dir cross_dev_prefix cc_march cflags cppflags verbose project_name lib_src
	set     cmd "make -f $tool_dir/lib/gen_static_stubs.mk"
	lappend cmd "LIBS=[join $libs { }]"
	lappend cmd "TOOL_DIR=$tool_dir"
	lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
	lappend cmd "ABI_DIR=$abi_dir"
	lappend cmd "CC_MARCH=[join $cc_march { }]"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "RUST_COMPAT_LIB=$lib_src"
	diag "generate static library stubs via command: [join $cmd { }]"

	if {[catch { exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:stubs\] /" >@ stdout }]} {
		exit_with_error "failed to generate static library stubs for the following libraries:\n" \
		                [join $used_apis "\n "] }
}



proc build { } {

	global build_dir cross_dev_prefix verbose project_name jobs project_dir
	global cppflags cflags cxxflags ldflags ldlibs_common ldlibs_exe ldlibs_so lib_src
	global cc_march

	set rustflags { }
	set gcc_unwind [exec $cross_dev_prefix\gcc $cc_march -print-file-name=libgcc_eh.a]
	lappend ldflags $gcc_unwind

	foreach x $ldflags {
		lappend rustflags -C link-arg=$x
	}

	foreach x $ldlibs_common {
		lappend rustflags -C link-arg=$x
	}

	foreach x $ldlibs_exe {
		lappend rustflags -C link-arg=$x
	}

	set ::env(RUSTFLAGS) $rustflags
	set ::env(RUST_STD_FREEBSD_12_ABI) 1

	set fake_libs { execinfo pthread gcc_s c m rt util memstat kvm procstat devstat }

	generate_static_stubs $fake_libs

	set cmd { }
	lappend cmd cargo build
	lappend cmd "-r"
	lappend cmd "--target" x86_64-unknown-freebsd
	lappend cmd --config target.x86_64-unknown-freebsd.linker="$cross_dev_prefix\gcc"
	lappend cmd --config profile.release.panic="abort"

	set copy [list cp -f -l]

	if {$verbose == 1} {
		lappend cmd "-vv"
		lappend copy "-v"
	} else {
		lappend cmd "-q"
	}

	set orig_pwd [pwd]
	cd $build_dir
	diag "build via command" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cargo\] /" >@ stdout} msg]} {
		exit_with_error "build via cargo failed: $msg" }

	diag "copy release binaries"
	set binaries [exec find target/x86_64-unknown-freebsd/release -maxdepth 1 -type f -executable]
	lappend copy $binaries .

	if {[catch {exec -ignorestderr {*}$copy | sed "s/^/\[$project_name:copy\] /" >@ stdout} msg]} {
		exit_with_error "moving release binary failed: $msg" }

	cd $orig_pwd
}
