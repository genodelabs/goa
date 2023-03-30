
proc exit_with_error { args } {
	puts stderr "Error: [join $args { }]"
	exit 1
}


##
# Print diagnostic message in verbose mode
#
proc diag { args } {
	global verbose project_name
	if {$verbose} {
		puts "\[$project_name\] [join $args { }]" }
}


##
# Unconditionally print message, prefixed with the project name
#
proc log { args } {
	global project_name
	puts "\[$project_name\] [join $args { }]"
}


proc _consume_cmdline_arg_at { tag_idx } {
	global argv

	set next_idx [expr $tag_idx + 1]

	# stop if argv ends with the argument name
	if {$next_idx >= [llength $argv]} {
		exit_with_error "missing value of command-line-argument" \
		                "[lindex $argv $tag_idx]" }

	# return list element following the argument name
	lappend result [lindex $argv $next_idx]

	# prune argv by the consumed argument tag and value
	set argv [lreplace $argv $tag_idx $next_idx]

	return $result
}


##
# Determine value of command-line argument and remove arg from argv
#
# \return argument value
#
proc consume_required_cmdline_arg { tag } {
	global argv

	# find argument name in argv list
	set tag_idx_list [lsearch -all $argv $tag]

	if {[llength $tag_idx_list] == 0} {
		exit_with_error "missing command-line argument $tag" }

	if {[llength $tag_idx_list] > 1} {
		exit_with_error "command-line argument $tag specfied more than once" }

	return [_consume_cmdline_arg_at [lindex $tag_idx_list 0]]
}


##
# Determine value of optional command-line argument and remove arg from argv
#
# \return argument value
#
proc consume_optional_cmdline_arg { tag default_value } {
	global argv

	# find argument name in argv list
	set tag_idx_list [lsearch -all $argv $tag]

	if {[llength $tag_idx_list] == 0} {
		return $default_value }

	if {[llength $tag_idx_list] > 1} {
		exit_with_error "command-line argument $tag specfied more than once" }

	return [_consume_cmdline_arg_at [lindex $tag_idx_list 0]]
}


##
# Consume optional command-line switch
#
# \return 1 if command-line switch was specified
#
proc consume_optional_cmdline_switch { tag } {
	global argv

	# find argument name in argv list
	set tag_idx_list [lsearch -all $argv $tag]

	if {[llength $tag_idx_list] == 0} {
		return 0 }

	if {[llength $tag_idx_list] > 1} {
		exit_with_error "command-line switch $tag specfied more than once" }

	# prune argv by the consumed switch tag
	set tag_idx [lindex $tag_idx_list 0]
	set argv [lreplace $argv $tag_idx $tag_idx]

	return 1
}


proc read_file_content { path } {

	# return empty string if file does not exist
	if {![file exists $path]} {
		return {} }

	set fh [open $path RDONLY]
	set content [read $fh]
	close $fh
	return $content
}


proc read_file_content_as_list { path } {

	set lines [split [read_file_content $path] "\n"]
	set result { }
	foreach line $lines {

		# ignore comments
		regsub {#.*$} $line {}  line

		# remove trailing space
		regsub {\s+$} $line { } line

		# append non-empty line to result list
		if {$line != ""} {
			lappend result $line }
	}
	return $result
}


##
# Supplement list of archives with version information found in .goarc files
#
# This procedure expects that each archive is specified with either 3 (without
# version) or 4 (with version) elements. Hence, it must not be called for
# binary archives, which may have 4 or 5 elements.
#
proc apply_versions { archive_list } {
	global version versions_from_genode_dir

	set versioned_archives { }
	foreach archive $archive_list {

		set elements [split $archive "/"]

		if {[llength $elements] < 3 || [llength $elements] > 4} {
			exit_with_error "invalid depot-archive path '$archive'" }

		set type [lindex $elements 1]
		set name [lindex $elements 2]

		if {$type == "bin"} {
			exit_with_error "unexpected depot-archive type 'bin'" }

		# version is already specified
		if {[llength $elements] == 4} {
			lappend versioned_archives $archive
			continue
		}

		# try to obtain current version from genode source tree if configured
		if {[info exists versions_from_genode_dir]} {
			set hash_file [glob -nocomplain $versions_from_genode_dir/repos/*/recipes/$type/$name/hash]

			set recipe_version [lindex [read_file_content $hash_file] 0]
			if {$recipe_version != ""} {
				diag "using recipe version $recipe_version for $archive"
				set version($archive) $recipe_version
			}
		}

		if {![info exists version($archive)]} {
			exit_with_error "no version defined for depot archive '$archive'" }

		lappend versioned_archives "$archive/$version($archive)"
	}
	return $versioned_archives
}


##
# Return list of binary archives for a given list of versioned source archives
#
proc binary_archives { archive_list } {
	global arch depot_dir

	set bin_archives { }
	foreach archive $archive_list {

		set elements [split $archive "/"]

		set user    [lindex $elements 0]
		set type    [lindex $elements 1]
		set name    [lindex $elements 2]
		set version [lindex $elements 3]

		if {$type == "src"} {
			lappend bin_archives "$user/bin/$arch/$name/$version" }

		if {$type == "raw"} {
			lappend bin_archives $archive }

		if {$type == "pkg"} {
			set pkg_archives_file [file join $depot_dir $archive archives]

			if {[file exists $pkg_archives_file]} {
				# add archive paths to installed archive content
				set pkg_archives [read_file_content_as_list $pkg_archives_file]

				#
				# XXX detect cyclic dependencies between pkg archives
				#
				lappend bin_archives {*}[binary_archives $pkg_archives]
			} else {
				# archive path for pkg yet to install
				lappend bin_archives "$user/pkg/$arch/$name/$version"
			}
		}
	}
	return $bin_archives
}


##
# Return name element of specified archive path
#
proc archive_name { archive } {
	set elements [split $archive "/"]
	if {[llength $elements] < 3} {
		return "" }
	return [lindex $elements 2]
}


proc api_archive_dir { api_name } {
	global used_apis depot_dir
	foreach archive $used_apis {
		set elements [split $archive "/"]
		if {[llength $elements] == 4 && [lindex $elements 2] == $api_name} {
			return [file join $depot_dir $archive] }
	}
	exit_with_error "could not find matching $api_name API in depot"
}


##
# Return list of ROM modules declared in a runtime file's <content> node
#
proc content_rom_modules { runtime_file } {

	set attributes { }
	catch {
		set attributes [query_node "/runtime/content/rom/attribute::label" $runtime_file]
	}

	set rom_names { }
	foreach attr $attributes {
		regexp {"(.*)"} $attr dummy rom_name
		lappend rom_names $rom_name
	}
	return $rom_names
}


##
# Return list of required file systems (pair of label/writeable) declared in a
# runtime file's <requires> node
#
proc required_file_systems { runtime_file } {

	set num_fs [exec xmllint --xpath "count(/runtime/requires/file_system)"  $runtime_file]

	# Request attribute value from nth <file_system> node
	proc file_system_attr { runtime_file n attr_name default_value } {

		set value [exec xmllint \
		                --xpath "string(/runtime/requires/file_system\[$n\]/@$attr_name)" \
		                $runtime_file]
		if {$value != ""} {
			return $value }

		return $default_value
	}

	set file_systems { }

	# iterate over <file_system> nodes
	for {set i 1} {$i <= $num_fs} {incr i} {

		set label     [file_system_attr $runtime_file $i "label"     ""]
		set writeable [file_system_attr $runtime_file $i "writeable" "no"]

		if {$label == ""} {
			puts stderr "Warning: file systems without labels will be ignored"
		} else {
			lappend file_systems $label $writeable
		}
	}

	return $file_systems
}


##
# Create symlinks for each file found at 'from_dir' in 'to_dir'
#
proc symlink_directory_content { file_whitelist from_dir to_dir } {

	if {![file exists $from_dir] || ![file isdirectory $from_dir]} {
		return }

	set from_files [glob -nocomplain -directory $from_dir *]
	foreach from_file $from_files {

		set name [file tail $from_file]

		# don't symlink file when absent from the 'file_whitelist'
		if {[lsearch $file_whitelist $name] == -1} {
			continue }

		set symlink_path [file join $to_dir $name]

		if {[file exists $symlink_path]} {
			file delete $symlink_path }

		file link $symlink_path $from_file
	}
}


##
# Create symlink-based mirror of the source-directory structure at the build
# directory
#
proc mirror_source_dir_to_build_dir { } {

	global build_dir
	global project_dir

	#
	# Mirror structure of source dir in build dir using symbolic links
	#

	set saved_pwd [pwd]
	cd src
	set dirs  [exec find . -type d]
	set files [split [exec find . -not -type d -and -not -name "*~"] "\n"]
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


##
# Install Genode config into run directory
#
proc install_config { args } {
	global run_dir
	set fh [open [file join $run_dir config] "WRONLY CREAT TRUNC"]
	set lines [split [join $args {}] "\n"]

	# strip common indentation
	set min_indent 1000
	foreach line $lines {
		if {[regexp {^\s*$} $line dummy]} { continue }
		regexp {^\t+} $line indentation
		set num_leading_tabs [string length $indentation]
		if {$num_leading_tabs < $min_indent} {
			set min_indent $num_leading_tabs }
	}

	foreach line $lines {

		# leading tabs
		regsub "^\t{2}" $line "" line

		# empty lines and trailing space
		regsub {\s+$}   $line "" line
		puts $fh $line
	}

	close $fh
}


##
# Return true if specified program is installed
#
proc have_installed { program } {

	if {[auto_execok "$program"] != ""} { return true; }
	return false;
}


proc exit_if_not_installed { args } {

	set missing_programs { }
	foreach program $args {
		if {![have_installed $program]} {
			lappend missing_programs $program } }

	if {[llength $missing_programs] == 1} {
		exit_with_error "the program [lindex $missing_programs 0]" \
		                "is required by Goa but not installed on your host system" }

	if {[llength $missing_programs] > 1} {
		exit_with_error "the programs [join $missing_programs {, }]" \
		                "are required by Goa but not installed on your host system" }
}


##
# Check syntax of specified XML file using xmllint
#
proc check_xml_syntax { xml_file } {

	if {[catch {exec xmllint --noout $xml_file} result]} {
		exit_with_error "invalid XML syntax in $xml_file:\n$result" }
}


proc query_attr { node_path attr_name xml_file }  {
	set xpath "$node_path/attribute::$attr_name"
        set attr_value [exec xmllint --xpath $xpath $xml_file]
	# in the presence of multiple matching xpaths, return only the first
	regexp {"(.*)"} [lindex $attr_value 0] dummy value
	return $value
}


proc query_attrs { node_path attr_name xml_file }  {
        set xpath "$node_path/attribute::$attr_name"
        set attr_value [exec xmllint --xpath $xpath $xml_file]
        # in the presence of multiple matching xpaths, return only the first
        set matches [regexp -all -inline {"([^"]*)"} $attr_value]
        set values {}
        foreach {match capture} $matches {
            lappend values $capture
        }
        return $values
}


proc query_node { node_path xml_file }  {

	set xpath "$node_path"
	set content [exec xmllint --xpath $xpath $xml_file]

	return $content
}


proc desanitize_xml_characters { string } {
	regsub -all {&gt;} $string {>} string
	regsub -all {&lt;} $string {<} string
	return $string
}


proc try_query_attr_from_runtime { attr } {
	global runtime_file

	if {[catch {
		set result [query_attr /runtime $attr $runtime_file]
	}]} {
		exit_with_error "missing '$attr' attribute in <runtime> at $runtime_file"
	}
	return $result
}


proc goa_git { args } {
	global tool_dir
	return [exec -ignorestderr git -C $tool_dir {*}$args]
}


proc current_goa_branch { } {
	if {![have_installed git]} { return "unknown" }
	return [lindex [goa_git  rev-parse --abbrev-ref HEAD] end]
}
