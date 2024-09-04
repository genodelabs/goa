##
# Import action and helpers
#

namespace eval goa {
	namespace export import diff

	proc calc_import_hash { } {

		global tool_dir config::project_dir

		set     cmd "make"
		lappend cmd "-f" [file join $tool_dir ports mk print_hash.mk]
		lappend cmd "-s"
		lappend cmd "PORT=[file join $project_dir import]"
		lappend cmd "REP_DIR=$project_dir"
		lappend cmd "PORTS_TOOL_DIR=[file join $tool_dir ports]"

		return [exec {*}$cmd]
	}


	##
	# Return 1 if the specified src/ or raw/ sub directory contains local changes
	#
	proc check_modified { subdir } {

		global config::contrib_dir

		set dir_a [file join $contrib_dir $subdir]
		set dir_b [file join $subdir]

		if {![file exists $dir_a] || ![file isdirectory $dir_a]} { return 0 }
		if {![file exists $dir_b] || ![file isdirectory $dir_b]} { return 0 }

		return [catch {
			exec -ignorestderr diff -u -r --exclude=.git --exclude=*~ $dir_a $dir_b
		}]
	}


	##
	# Diff between originally imported contrib code and local edits
	#
	proc diff { subdir } {
		global config::contrib_dir

		set dir_a [file join $contrib_dir $subdir]
		set dir_b [file join $subdir]

		if {![file exists $dir_a] || ![file isdirectory $dir_a]} { return }
		if {![file exists $dir_b] || ![file isdirectory $dir_b]} { return }

		catch {
			#
			# Filter the diff output via tail to strip the first two lines from the
			# output. Those lines would show the diff command and the absolute path
			# to 'contrib_dir'.
			#
			# The argument -N is specified o show the content new files.
			#
			exec -ignorestderr diff -N -u -r --exclude=.git --exclude=*~ $dir_a $dir_b \
			                   | tail -n +3 >@ stdout
		}
	}


	##
	# Implements 'goa import'
	#
	proc import { } {

		global verbose tool_dir
		global config::contrib_dir config::jobs config::project_dir
		global config::build_dir config::import_dir

		if {![file exists import] || ![file isfile import]} {
			exit_with_error "missing 'import' file" }

		# quick-check the import.hash to detect the need for re-import
		set need_fresh_import 0
		set existing_hash [read_file_content_as_list [file join $contrib_dir import.hash]]

		if {$existing_hash != [calc_import_hash]} {
			set need_fresh_import 1 }

		if {$need_fresh_import} {

			# abort import if there are local changes in src/ or raw/
			foreach subdir [list src raw] {
				if {[check_modified $subdir]} {
					exit_with_error "$subdir/ contains local changes," \
					                 "review via 'goa diff'" } }

			if {[file exists $contrib_dir]} {
				file delete -force $contrib_dir }

			file mkdir $contrib_dir

			set     cmd "make"
			lappend cmd "-f" [file join $tool_dir ports mk install.mk]
			lappend cmd "-C" $contrib_dir
			lappend cmd "-j$jobs"
			lappend cmd "-s"
			lappend cmd "PORT=[file join $project_dir import]"
			lappend cmd "REP_DIR=$project_dir"
			lappend cmd "PORTS_TOOL_DIR=[file join $tool_dir ports]"
			lappend cmd "GENODE_CONTRIB_CACHE=$import_dir"

			if {$verbose} {
				lappend cmd "VERBOSE=" }

			diag "import via command: $cmd"

			if {[catch { exec {*}$cmd >@ stdout 2>@ stdout }]} {
				exit_with_error "import failed" }

			foreach subdir [list src raw] {

				set src_dir [file join $contrib_dir $subdir]
				set dst_dir [file join $project_dir $subdir]

				if {[file exists $src_dir] && [file exists $dst_dir]} {
					file delete -force $dst_dir }

				if {[file exists $src_dir]} {
					file copy -force $src_dir $dst_dir }
			}

			file delete -force $build_dir

		} else {

			foreach subdir [list src raw] {

				set src_dir [file join $contrib_dir $subdir]
				set dst_dir [file join $project_dir $subdir]

				if {[file exists $src_dir] && ![file exists $dst_dir]} {
					file copy -force $src_dir $dst_dir }
			}
		}
	}
}
