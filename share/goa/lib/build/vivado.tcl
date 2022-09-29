
proc create_or_update_build_dir { } {

	global build_dir project_dir verbose
	global project_name

	# skip if project file already exists
	if {[file exists [glob -nocomplain [file join $build_dir * *.xpr]]]} {
		return
	}

	if {![file exists $build_dir]} {
		file mkdir $build_dir }

	set orig_pwd [pwd]
	cd $build_dir

	set cmd { }
	lappend cmd vivado
	lappend cmd "-nolog"
	lappend cmd "-nojournal"
	lappend cmd "-mode"
	lappend cmd "batch"
	lappend cmd "-source"
	lappend cmd "[file join $project_dir src vivado.tcl]"
	if {$verbose != 0} {
		lappend cmd "-verbose"
	}
	lappend cmd "-tclargs"
	lappend cmd "--origin_dir"
	lappend cmd "[file join $orig_pwd src]"
	lappend cmd "--project_name"
	lappend cmd "vivado"

	diag "create build directory via command:" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "/^#.*/d" | sed "s/^/\[$project_name:vivado\] /" >@ stdout} msg]} {
		exit_with_error "build-directory creation via vivado failed:\n" $msg }

	cd $orig_pwd
}


proc build { } {
	global build_dir jobs project_name verbose tool_dir

	set target "$project_name.bit"
	if {[file exists [file join $build_dir $target]]} {
		return
	}

	set orig_pwd [pwd]
	cd $build_dir

	set cmd { }
	lappend cmd vivado
	lappend cmd "-nolog"
	lappend cmd "-nojournal"
	lappend cmd "-mode"
	lappend cmd "batch"
	lappend cmd "-source"
	lappend cmd "[file join $tool_dir vivado generate_bitstream.tcl]"
	if {$verbose != 0} {
		lappend cmd "-verbose"
	}
	lappend cmd "-tclargs"
	lappend cmd "--jobs"
	lappend cmd $jobs"
	lappend cmd "--target"
	lappend cmd $target"

	diag "generating bitstream via command:" {*}$cmd

	if {[catch {exec {*}$cmd | sed "/^#.*/d" | sed "s/^/\[$project_name:vivado\] /" >@ stdout} msg]} {
		exit_with_error "build via vivado failed:\n" $msg }

	cd $orig_pwd
}
