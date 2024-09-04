##
# Version-related actions (require project directory)
#

namespace eval goa {
	namespace export archive-versions bump-version

	proc bump-version { target_version } {

		global project_dir

		set version_file [file join $project_dir version]
		if {[file exists $version_file]} {
			set old_version ""

			catch {
				set old_version [project_version $project_dir] }

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
		global depot_user

		# get supported archs
		if {[catch { set supported_archs [query_attrs_from_file /index/supports arch $index_file] }]} {
			exit_with_error "missing <supports arch=\"...\"/> in index file" }

		# helper proc to apply archs to paths found in a list of <pkg> nodes
		proc _paths_with_arch { pkgs archs } {
			set res ""
			foreach pkg $pkgs {
				set path [query_from_string string(/pkg/@path) $pkg ""]
				set pkg_archs $archs
				catch {
					set pkg_archs [query_attrs_from_string /pkg arch $pkg] }

				lappend res $path $pkg_archs
			}
			return $res
		}

		# helper for recursive processing of index nodes
		proc _index_with_arch { xml archs result } {
			# iterate <index> nodes
			catch {
				foreach index_xml [split [query_from_string /index/index $xml ""] \n] {
					set index_archs [split [query_from_string string(/index/@arch) $index_xml "$archs"] " "]
					set index_name [query_from_string string(/index/@name) $index_xml ""]
					set pkgs [split [query_from_string /index/pkg $index_xml ""] \n]
					lappend result {*}[_paths_with_arch $pkgs $index_archs]

					set result [_index_with_arch $index_xml $index_archs $result]
				}
			}
			return $result
		}

		return [_index_with_arch [query_from_file /index $index_file] $supported_archs ""]
	}


	proc archive-versions { } {

		global versions_from_genode_dir depot_user version project_dir

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
				lappend archives "$depot_user/pkg/$pkg_name" }
		}

		set archives [lsort -unique $archives]
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
