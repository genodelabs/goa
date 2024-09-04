##
# Run action and helpers
#

namespace eval goa {
	namespace export run-dir

	#
	# set roms found in depot runtime files
	#
	proc update_depot_roms { archive_list &rom_modules } {

		global depot_dir
		upvar  ${&rom_modules} rom_modules

		# append rom modules of runtimes
		foreach runtime_file [runtime_files [apply_versions $archive_list]] {
			append rom_modules " " [query_attrs_from_file /runtime/content/rom label $runtime_file]
		}
	}


	proc run-dir { } {

		global tool_dir project_dir run_pkg run_dir dbg_dir bin_dir depot_dir
		global debug
	
		set pkg_dir [file join $project_dir pkg $run_pkg]
	
		if {![file exists $pkg_dir]} {
			exit_with_error "no runtime defined at $pkg_dir" }
	
		# install depot content needed according to the pkg's archives definition
		set archives_file [file join $pkg_dir archives]
		set runtime_archives [read_file_content_as_list $archives_file]
	
		# init empty run directory
		if {[file exists $run_dir]} {
			file delete -force $run_dir }
		file mkdir $run_dir
	
		if { $debug } {
			file mkdir [file join $run_dir .debug] }
	
		#
		# Generate Genode config depending on the pkg runtime specification. The
		# procedure may extend the lists of 'runtime_archives' and 'rom_modules'.
		#
		set runtime_file [file join $pkg_dir runtime]
	
		if {![file exists $runtime_file]} {
			exit_with_error "missing runtime configuration at: $runtime_file" }
	
		# check XML syntax of runtime config and config file at raw/
		check_xml_syntax $runtime_file
		foreach config_file [glob -nocomplain [file join raw *.config]] {
			check_xml_syntax $config_file }
		
		#
		# Partially prepare depot before calling 'generate_runtime_config'.
		# For plausability checks, the latter needs access to the included ROM modules.
		#
		set binary_archives [binary_archives [apply_versions $runtime_archives]]
		prepare_depot_with_archives $binary_archives
	
		set rom_modules { }
		generate_runtime_config $runtime_file runtime_archives rom_modules
	
		# prepare depot with additional archives added by 'generate_runtime_config'
		set binary_archives [binary_archives [apply_versions $runtime_archives]]
		prepare_depot_with_archives $binary_archives
		if { $debug } {
			prepare_depot_with_debug_archives $binary_archives }
	
		update_depot_roms $runtime_archives rom_modules
	
		# update 'binary_archives' with information available after installation
		set binary_archives [binary_archives [apply_versions $runtime_archives]]
	
		set debug_modules [lmap x $rom_modules {expr { "$x.debug" }}]
	
		# populate run directory with depot content
		foreach archive $binary_archives {
			symlink_directory_content $rom_modules [file join $depot_dir $archive] $run_dir
	
			# add debug info files
			if { $debug && [regsub {/bin/} $archive {/dbg/} debug_archive] } {
				symlink_directory_content $debug_modules [file join $depot_dir $debug_archive] [file join $run_dir .debug] }
		}
	
		# add artifacts as extracted from the build directory
		symlink_directory_content $rom_modules $bin_dir $run_dir
	
		# add debug info files as extracted from the build directory
		symlink_directory_content $debug_modules $dbg_dir [file join $run_dir .debug]
	
		# add content found in the project's raw/ subdirectory
		symlink_directory_content $rom_modules [file join $project_dir raw] $run_dir

	}
}
