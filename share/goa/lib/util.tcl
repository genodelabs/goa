
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
# Find archive in directory tree starting from the directory where Goa was
# called with -C
#
proc find_project_dir_for_archive { type name } {
	global original_dir

	set orig_pwd [pwd]
	set candidates ""

	set find_cmd_base [list find -not -path "*/depot/*" \
	                        -and -not -path "*/contrib/*" \
	                        -and -not -path "*/build/*" \
	                        -and -not -path "*/var/*"]

	cd $original_dir
	if {$type == "src" || $type == "bin"} {
		set candidates [exec {*}$find_cmd_base -and \( -path */$name/src \
		                                           -or -path */$name/import \
		                                           -or -path */$name/artifacts \)]
	} elseif {$type == "api"} {
		set candidates [exec {*}$find_cmd_base -and -path */$name/api -type f]
	} elseif {$type == "pkg"} {
		set candidates [exec {*}$find_cmd_base -and -path */pkg/$name -type d]
	} elseif {$type == "raw"} {
		set candidates [exec {*}$find_cmd_base -and -path */$name/raw -type d]
	}
	cd $orig_pwd

	regsub -line -all {(/(src|pkg/.*|raw|import|artifacts|api))$} $candidates "" candidates

	foreach dir $candidates {
		set absolute_path [file join $original_dir [string trimleft $dir "./"]]
		if {[looks_like_goa_project_dir $absolute_path]} {
			return $absolute_path }
	}

	return -code error
}


##
# Acquire project version from 'version' file
#
proc project_version { dir } {

	set version_file [file join $dir version]
	if {[file exists $version_file]} {
		set version_from_file [read_file_content $version_file]

		if {[llength $version_from_file] > 1} {
			exit_with_error "version defined at $version_file" \
			                "must not contain any whitespace" }

		if {$version_from_file == ""} {
			exit_with_error "$version_file is empty" }

		return [lindex $version_from_file 0]
	}

	return -code error "file $version_file does not exist"
}


##
# Supplement list of archives with version information found in .goarc files,
# in the genode directory, or in local Goa projects
#
# This procedure expects that each archive is specified with either 3 (without
# version) or 4 (with version) elements. Hence, it must not be called for
# binary archives, which may have 4 or 5 elements.
#
# If versions_from_genode_dir is set, version information from found in the
# specified genode directory supersedes version information found in .goarc
# files.
#
# If no version information is available, the original working directory is
# scanned for corresponding Goa projects.
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

		# try to obtain missing version information from Goa projects
		if {![info exists version($archive)]} {
			catch {
				set dir [find_project_dir_for_archive $type $name]
				set version($archive) [project_version $dir]
			}
		}

		# exit if version information is still missing
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


proc query_from_string { xpath node default_value } {

	set content [exec xmllint --xpath $xpath - << $node]

	if {$content == ""} {
		set content $default_value }

	return $content
}


proc query_attrs_from_string { node_path attr_name xml }  {

	set xpath "$node_path/attribute::$attr_name"
	set attributes [exec xmllint --xpath $xpath - << $xml]

	set values { }
	foreach attr $attributes {
		regexp {"(.*)"} $attr dummy value
		lappend values $value
	}
	return $values
}


proc query_attrs_from_file { node_path attr_name xml_file }  {

	set xpath "$node_path/attribute::$attr_name"
	set attributes [exec xmllint --xpath $xpath $xml_file]

	set values { }
	foreach attr $attributes {
		regexp {"(.*)"} $attr dummy value
		lappend values $value
	}
	return $values
}


proc query_attr_from_file { node_path attr_name xml_file }  {

	set xpath "$node_path/attribute::$attr_name"
	set attr_value [exec xmllint --xpath $xpath $xml_file]

	# in the presence of multiple matching xpaths, return only the first
	regexp {"(.*)"} [lindex $attr_value 0] dummy value
	return $value
}


proc query_from_file { node_path xml_file }  {

	set xpath "$node_path"
	set content [exec xmllint --xpath $xpath $xml_file]

	return $content
}


proc desanitize_xml_characters { string } {
	regsub -all {&gt;} $string {>} string
	regsub -all {&lt;} $string {<} string
	return $string
}


proc try_query_attr_from_file { runtime_file attr } {
	if {[catch {
		set result [query_attr_from_file /runtime $attr $runtime_file]
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


proc avail_goa_branches { } {
	if {![have_installed git]} { return "unknown" }

	set git_branch_output [goa_git branch --list -r |\
	                         sed "s/^..//" | grep "^origin" |\
	                         grep -v " -> " | sed "s#^origin/##"]

	return [split $git_branch_output "\n"]
}
