
proc create_or_update_build_dir { } { mirror_source_dir_to_build_dir }

proc generate_static_stubs { libs } {
	global tool_dir verbose cflags cppflags lib_src
	global config::abi_dir config::cross_dev_prefix config::cc_march config::project_name

	set     cmd "make -f $tool_dir/lib/gen_static_stubs.mk"
	lappend cmd "LIBS=[join $libs { }]"
	lappend cmd "TOOL_DIR=$tool_dir"
	lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
	lappend cmd "ABI_DIR=$abi_dir"
	lappend cmd "CC_MARCH=[join $cc_march { }]"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "RUST_COMPAT_LIB=$lib_src"
	if {$verbose == 1} {
		lappend cmd "VERBOSE=''"
	}
	diag "generate static library stubs via command: [join $cmd { }]"

	if {[catch { exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:stubs\] /" >@ stdout }]} {
		exit_with_error "failed to generate static library stubs for the following libraries:\n" \
		                [join $used_apis "\n "] }
}



proc build { } {

	global verbose tool_dir
	global cppflags cflags cxxflags ldflags ldlibs_common ldlibs_exe lib_src
	global config::build_dir config::cross_dev_prefix config::debug
	global config::project_name config::jobs config::project_dir config::cc_march

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
	if {!$debug} {
		lappend cmd "-r" }
	lappend cmd "--target" $tool_dir/cargo/x86_64-unknown-genode.json
	lappend cmd --config target.x86_64-unknown-genode.linker="$cross_dev_prefix\gcc"
	lappend cmd --config profile.release.panic="abort"
	lappend cmd --config profile.dev.panic="abort"
	# let cargo know we need to build panic_abort too, see
	# https://github.com/rust-lang/wg-cargo-std-aware/issues/29
	lappend cmd -Z build-std=std,panic_abort

	set copy [list cp -f -l]

	if {$verbose == 1} {
		lappend cmd "-vv"
		lappend copy "-v"
	}

	set orig_pwd [pwd]
	cd $build_dir
	diag "build via command" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:cargo\] /" >@ stdout} msg]} {
		exit_with_error "build via cargo failed: $msg" }

	if {$debug} {
		diag "copy debug binaries"
		set binaries [exec find target/x86_64-unknown-genode/debug -maxdepth 1 -type f -executable]
		lappend copy $binaries .

		if {[catch {exec -ignorestderr {*}$copy | sed "s/^/\[$project_name:copy\] /" >@ stdout} msg]} {
			exit_with_error "moving debug binary failed: $msg" }
	} else {
		diag "copy release binaries"
		set binaries [exec find target/x86_64-unknown-genode/release -maxdepth 1 -type f -executable]
		lappend copy $binaries .

		if {[catch {exec -ignorestderr {*}$copy | sed "s/^/\[$project_name:copy\] /" >@ stdout} msg]} {
			exit_with_error "moving release binary failed: $msg" }
	}

	cd $orig_pwd
}
