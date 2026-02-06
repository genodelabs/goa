##
# Run action and helpers
#

namespace eval goa {
	namespace export run-dir

	#
	# set roms found in depot runtime files
	#
	proc update_depot_roms { archive_list &rom_modules } {

		global config::depot_dir
		upvar  ${&rom_modules} rom_modules

		# append rom modules of runtimes
		foreach runtime_file [runtime_files [apply_versions $archive_list]] {
			append rom_modules " " [query attributes $runtime_file "runtime | + content | + rom | : label"]
		}
	}


	proc validate_init_config { binary_name config { max_depth 5 }} {
		global config::hsd_dir

		if {$max_depth == 0} {
			exit_with_error "maximum config depth exceeded during validation" }
		incr max_depth -1

		if {![file exists [file join $hsd_dir "$binary_name.hsd"]]} {
			return }

		try {
			hid tool $config check --hsd-dir $hsd_dir --schema $binary_name
		} trap CHILDSTATUS { msg } {
			exit_with_error "Schema validation failed for $binary_name:\n$msg"
		} on error { msg } { error $msg $::errorInfo }

		# check sub inits
		if {$binary_name == "init"} {
			set config_node [query node $config "+ config"]
			node for-each-node $config_node "start" start_node {
				set sub_binary_name ""
				# use start name as default binary name
				node with-attribute $start_node "name" name {
					set sub_binary_name $name }

				# look for explicitly named binary
				node for-each-node $start_node "binary" binary_node {
					node with-attribute $binary_node "name" name {
						set sub_binary_name $name } }

				try {
					# query for route to config file and validate
					set config_file [query attribute $start_node \
						"start_node | + route | + service ROM | label: config | + parent | : label"]
					validate_init_config $sub_binary_name $config_file $max_depth

				} trap ATTRIBUTE_MISSING { } {
					# validate inline config if present
					node for-each-node $start_node "config" config_node {
						validate_init_config $sub_binary_name $config_node $max_depth }
				}
			}
		}
	}


	proc run-dir { } {

		global tool_dir args
		global config::project_dir config::run_dir config::dbg_dir config::bin_dir
		global config::depot_dir config::debug config::hsd_dir config::hid
	
		set pkg_dir [file join $project_dir pkg $args(run_pkg)]
	
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
	
		# check runtime file against hsd
		try {
			hid tool $runtime_file check --hsd-dir [file join $tool_dir hsd] --schema runtime
		} trap CHILDSTATUS { msg } {
			exit_with_error "Schema validation failed for $runtime_file:\n$msg"
		} on error { msg } { error $msg $::errorInfo }

		# check syntax config files at raw/ against
		foreach config_file [glob -nocomplain [file join raw *.config]] {
			query validate-syntax $config_file }
		
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

		# skip remainder of this function in XML mode
		if {!$hid} { return }

		#
		# collect .hsd files from depot and build artifacts
		#
		
		# init empty hsd directory
		if {[file exists $hsd_dir]} {
			file delete -force $hsd_dir }
		file mkdir $hsd_dir

		# symlink hsd files from archives and build artifacts
		set hsd_files [lmap rom $rom_modules { expr { "$rom.hsd" } }]
		foreach archive $binary_archives {
			symlink_directory_content $hsd_files [file join $depot_dir $archive] $hsd_dir }
		symlink_directory_content $hsd_files $bin_dir $hsd_dir

		# check config against hsd files
		validate_init_config "init" [file join $run_dir config]
	}
}
