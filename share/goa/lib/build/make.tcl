
proc create_or_update_build_dir { } {

	global build_dir
	global project_dir

	#
	# Mirror structure of source dir in build dir using symbolic links
	#

	set saved_pwd [pwd]
	cd src
	set dirs  [exec find . -type d]
	set files [exec find . -not -type d -and -not -name "*~"]
	cd $saved_pwd

	foreach dir $dirs {
		regsub {^\./?} $dir "" dir
		file mkdir [file join "$build_dir" $dir]
	}

	set symlinks { }
	foreach file $files {
		regsub {^\./?} $file "" file
		lappend symlinks $file
	}

	foreach symlink $symlinks {
		set target [file join $project_dir src $symlink]
		set path   [file join $build_dir $symlink]

		if {[file exists $path]} {
			file delete $path }

		file link -symbolic $path $target
	}

	#
	# Delete broken symlinks in the build directory.
	# This can happen whenever a file in the source directory is renamed.
	#
	exec find -L $build_dir -type l -delete
}


proc build { } {

	global build_dir cross_dev_prefix verbose project_name jobs
	global cppflags cflags cxxflags ldflags ldlibs

	set cmd { }

	lappend cmd make -C $build_dir
	lappend cmd "CPPFLAGS=$cppflags"
	lappend cmd "CFLAGS=$cflags"
	lappend cmd "CXXFLAGS=$cxxflags"
	lappend cmd "LDFLAGS=$ldflags"
	lappend cmd "LDLIBS=$ldlibs"
	lappend cmd "CXX=$cross_dev_prefix\g++"
	lappend cmd "CC=$cross_dev_prefix\gcc"
	lappend cmd "-j$jobs"

	if {$verbose == 0} {
		lappend cmd "-s" }

	diag "build via command" {*}$cmd

	if {[catch {exec -ignorestderr {*}$cmd | sed "s/^/\[$project_name:make\] /" >@ stdout}]} {
		exit_with_error "build via make failed" }

}
