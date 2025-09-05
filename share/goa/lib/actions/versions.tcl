##
# Version-related actions (require project directory)
#

namespace eval goa {
	namespace export archive-versions bump-version

	proc bump-version { target_version } {

		global config::project_dir

		set version_file [file join $project_dir version]
		if {[file exists $version_file]} {

			try {
				set old_version [project_version_from_file $project_dir]
			} trap NOT_FOUND { } {
				set old_version ""
			} on error { msg }   { error $msg $::errorInfo }

			# version already bumped?
			if {[string first $target_version $old_version] == 0} {
				set elements [split $old_version -]
				set suffix [lindex $elements end]
				if {[llength $elements] > 3 && [regexp {[a-y]} $suffix dummy]} {
					# bump suffix
					set new_suffix [format %c [expr [scan $suffix %c]+1]]
					set target_version [join [lreplace $elements end end $new_suffix] -]
				} else {
					# add suffix
					set target_version "$old_version-a"
				}
			}
		}

		set fd [open $version_file w]
		puts $fd $target_version
		close $fd
	}


	##
	# Get a list of pkg+arch-list pairs from an index file
	#
	proc pkgs_from_index { index_file } {
		# get supported archs
		set supported_archs [query attributes $index_file "index | + supports | : arch"]
		if {[llength $supported_archs] == 0} {
			exit_with_error "missing '+ supports arch: ...' in index file" }

		# helper for recursive processing of index nodes
		proc _index_with_arch { input archs result } {
			global ::config::depot_user

			# iterate <index> nodes
			node for-each-node $input "index" node {
				node with-attribute $node "arch" value {
					set archs [list $value]
				} default { }

				node for-each-node $node "pkg" pkg_node {

					node with-attribute $pkg_node "arch" value {
						set pkg_archs [list $value]
					} default {
						set pkg_archs $archs
					}

					node with-attribute $pkg_node "path" value {
						try {
							archive_user $value
						} trap INVALID_ARCHIVE { } {
							set value $depot_user/pkg/$value
						} on error { msg } { error $msg $::errorInfo }
					
						lappend result $value $pkg_archs
					} default {
						exit_with_error "Missing 'path' attribute for 'pkg' node in index file"
					}
				}

				set result [_index_with_arch $node $archs $result]
			}
			return $result
		}

		return [_index_with_arch [query node $index_file "index"] $supported_archs ""]
	}


	proc archive-versions { } {

		global config::versions_from_genode_dir config::depot_user config::version
		global config::project_dir

		if {[info exists versions_from_genode_dir] && [info exists depot_user]} {

			puts "#\n# depot-archive versions from $versions_from_genode_dir\n#"
			set repos [glob -nocomplain [file join $versions_from_genode_dir repos *]]
			foreach rep_dir $repos {
				set hash_files [glob -nocomplain [file join $rep_dir recipes * * hash]]
				if {[llength $hash_files] > 0} {
					puts "\n# repos/[file tail $rep_dir]"
					set lines { }
					foreach hash_file $hash_files {
						set name [file tail [file dirname $hash_file]]
						set type [file tail [file dirname [file dirname $hash_file]]]
						set vers [lindex [read_file_content $hash_file] 0]
						lappend lines "set version($depot_user/$type/$name) $vers"
					}
					set lines [lsort $lines]
					foreach line $lines {
						puts "$line"
					}
				}
			}
		}

		puts "\n#\n# depot-archive versions referenced by $project_dir\n#"
		set archives [read_file_content_as_list used_apis]
		set archive_files [glob -nocomplain [file join $project_dir pkg * archives]]
		foreach file $archive_files {
			set archives [concat $archives [read_file_content_as_list $file]] }

		set index_file [file join $project_dir index]
		if {[file exists $index_file] && [info exists depot_user]} {
			foreach { pkg_name pkg_archs } [pkgs_from_index $index_file] {
				lappend archives $pkg_name }
		}

		set archives [lsort -unique $archives]
		# Note: omitting 'validate_archives' because 'apply_versions' does it
		set versioned_archives [apply_versions $archives]
		foreach a $archives v $versioned_archives {
			set vers [archive_version $v]
			puts "set version($a) $vers"
		}

		puts "\n#\n# additional depot-archive versions from goarc\n#"
		if {[info exists version]} {
			foreach archive [array names version] {
				if {[lsearch -exact $archives $archive] < 0} {
					puts "set version($archive) $version($archive)" } } }
		puts ""
	}
}
