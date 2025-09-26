
proc create_or_update_build_dir { } { mirror_source_dir_to_build_dir }

proc generate_static_stubs { libs } {
	global tool_dir verbose cflags cppflags
	global config::abi_dir config::cross_dev_prefix config::cc_march config::project_name

	set     cmd [sandboxed_build_command]
	lappend cmd --bind $abi_dir

	lappend cmd make -f $tool_dir/lib/gen_static_stubs.mk
	lappend cmd "LIBS=[join $libs { }]"
	lappend cmd "TOOL_DIR=$tool_dir"
	lappend cmd "CROSS_DEV_PREFIX=$cross_dev_prefix"
	lappend cmd "ABI_DIR=$abi_dir"
	lappend cmd "CC_MARCH=[join $cc_march { }]"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CPPFLAGS=$cppflags"
	if {$verbose == 1} {
		lappend cmd "VERBOSE=''"
	}
	diag "generate static library stubs"

	if {[catch { exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:stubs\] /" >@ stdout }]} {
		exit_with_error "failed to generate static library stubs for the following libraries:\n" \
		                [join $libs "\n "] }
}


proc prepare_toolchain { } {
	global tool_dir verbose rustup_home cargo_home cargo_path
	global config::arch config::install_dir

	set install_rust_helper [file join $tool_dir install_rust_toolchain.mk]

	set rustup_home [file join $::env(HOME) .rustup]
	if {[info exists ::env(RUSTUP_HOME)]} {
		set rustup_home $::env(RUSTUP_HOME) }

	set cargo_home [file join $::env(HOME) .cargo]
	if {[info exists ::env(CARGO_HOME)]} {
		set cargo_home $::env(CARGO_HOME)
	}

	if {[file exists [file join $cargo_home bin]]} {
		set cargo_path [file join $cargo_home bin]
	}

	set cmd [sandboxed_build_command]
	lappend cmd --ro-bind $rustup_home
	lappend cmd --ro-bind $cargo_home
	lappend cmd --env-path [file join $cargo_home bin]
	lappend cmd $install_rust_helper query

	if {[catch {exec {*}$cmd}]} {
		set rustup_home [file join $install_dir rustup]
		set cargo_home  [file join $install_dir cargo]
		log "Using custom rust toolchain in $rustup_home"
		file mkdir $rustup_home
		file mkdir $cargo_home

		set cmd [sandboxed_build_command]
		lappend cmd --bind $rustup_home
		lappend cmd --bind $cargo_home
		lappend cmd --with-network
		lappend cmd --setenv RUSTUP_HOME $rustup_home
		lappend cmd --setenv CARGO_HOME  $cargo_home
		if {[info exists cargo_path]} {
			lappend cmd --ro-bind  $cargo_path
			lappend cmd --env-path $cargo_path
		}
		lappend cmd $install_rust_helper install
		exec -ignorestderr {*}$cmd
	}
}


proc build { } {

	global verbose tool_dir rustup_home cargo_home cargo_path
	global cppflags cflags cxxflags ldflags ldlibs_common ldlibs_exe
	global config::build_dir config::cross_dev_prefix config::debug config::arch
	global config::project_name config::jobs config::project_dir config::cc_march

	if {$arch != "x86_64"} {
		exit_with_error "Cargo/rust support is limited to x86_64." }

	set rustflags { }
	set gcc_unwind [exec_tool_chain gcc $cc_march -print-file-name=libgcc_eh.a]
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

	set fake_libs { execinfo pthread gcc_s c m rt util memstat kvm procstat devstat }

	generate_static_stubs $fake_libs

	prepare_toolchain

	set     cmd [sandboxed_build_command]
	lappend cmd --setenv RUSTFLAGS $rustflags
	lappend cmd --setenv RUST_STD_FREEBSD_12_ABI 1
	lappend cmd --setenv RUSTUP_HOME $rustup_home
	lappend cmd --setenv CARGO_HOME  $cargo_home
	if {[info exists cargo_path]} {
		lappend cmd --ro-bind  $cargo_path
		lappend cmd --env-path $cargo_path
	}
	lappend cmd --bind $rustup_home
	lappend cmd --bind $cargo_home
	lappend cmd --with-network
	lappend cmd cargo build
	if {!$debug} {
		lappend cmd "-r" }
	lappend cmd "--target" $tool_dir/cargo/x86_64-unknown-genode.json
	lappend cmd --config target.x86_64-unknown-genode.linker='\"$cross_dev_prefix\gcc\"'
	lappend cmd --config profile.release.panic='\"abort\"'
	lappend cmd --config profile.dev.panic='\"abort\"'
	# let cargo know we need to build panic_abort too, see
	# https://github.com/rust-lang/wg-cargo-std-aware/issues/29
	lappend cmd -Z build-std=std,panic_abort

	set     copy [sandboxed_build_command]
	lappend copy cp -f -l

	if {$verbose == 1} {
		lappend cmd "-vv"
		lappend copy "-v"
	}

	set orig_pwd [pwd]
	cd $build_dir
	diag "build via cargo"

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
