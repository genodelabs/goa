#
# goarc management
#

namespace eval ::config {
	namespace export path_var_names load_goarc_files set_late_defaults

	# defaults, potentially being overwritten by 'goarc' files
	# Note: All variables in this namespace can be overwritten by 'goarc' files
	variable project_dir              [pwd]
	variable project_name             [file tail $project_dir]
	variable arch                     ""
	variable cross_dev_prefix         ""
	variable rebuild                  0
	variable jobs                     1
	variable warn_strict              ""
	variable ld_march                 ""
	variable cc_march                 ""
	variable olevel                   "-O2"
	variable debug                    0
	variable versions_from_genode_dir ""
	variable depot_overwrite          0
	variable depot_retain             0
	variable license                  ""
	variable depot_user               ""
	variable run_as                   "genodelabs"
	variable target                   "linux"
	variable sculpt_version           ""
	variable cc_cxx_opt_std           "-std=gnu++20"
	variable binary_name              ""
	variable with_backtrace           0
	variable common_var_dir           ""
	variable search_dir               $::original_dir
	variable depot_dir                ""
	variable public_dir               ""
	variable contrib_dir              ""
	variable import_dir               ""
	variable abi_dir                  ""
	variable build_dir                ""
	variable run_dir                  ""
	variable bin_dir                  ""
	variable dbg_dir                  ""
	variable target_opt
	array set target_opt {}
	variable version
	array set version {}


	# if /proc/cpuinfo exists, use number of CPUs as 'jobs'
	if {[file exists /proc/cpuinfo]} {
		catch {
			set num_cpus [exec grep "processor.*:" /proc/cpuinfo | wc -l]
			set jobs $num_cpus
			diag "use $jobs jobs according to /proc/cpuinfo"
		}
	}


	# return names of path variables
	proc path_var_names {} {
		return [info vars ::config::*_dir] }


	proc _path_var { name } {
		if {[lsearch -exact [path_var_names] ::config::$name] >= 0} {
			return 1 }

		return [expr [string equal $name "cross_dev_prefix"] \
		          || [string equal $name "license"]]
	}


	# used as alias for 'set' in child interpreter
	proc _safe_set { rcfile args } {
		set nargs [llength $args]
		if {$nargs < 1} { return }

		set name [lindex $args 0]

		if {![info exists ::config::[lindex [split $name "("] 0]]} {
			diag "variable '$name' defined in $rcfile is not a config variable"
			return
		}

		if {$nargs == 1} {
			return [set ::config::$name] }

		set value [string trim [lindex $args 1]]

		if {[llength $value] > 1} {
			exit_with_error "$rcfile contains malformed definition of $name" }

		if {![_path_var $name]} {
			# non-path variables must not contain slashes
			if {[string first / $value] >= 0} {
				exit_with_error "Variable definition of '$name' in $rcfile" \
				                "must not contain slashes."
			}
		} else {
			# de-reference home directory
			regsub {^~} $::env(HOME) value

			# convert relative path to absolute path
			set value [file normalize $value]
		}

		return [set ::config::$name $value]
	}


	proc load_goarc_files {} {
		global tool_dir config::project_dir

		interp create -safe safeinterp
		safeinterp hide set

		set rcfile [file join $tool_dir goarc]
		safeinterp alias set config::_safe_set $rcfile
		safeinterp invokehidden source $rcfile

		#
		# Read the hierarcy of 'goarc' files
		#

		set goarc_path_elements [file split $project_dir]
		set goarc_name "goarc"
		set goarc_path [file separator]

		foreach path_elem $goarc_path_elements {

			set goarc_path           [file join $goarc_path $path_elem]
			set goarc_path_candidate [file join $goarc_path $goarc_name]
			set deprecated_goarc     [file join $goarc_path .$goarc_name]

			if {[file exists $deprecated_goarc]} {
				log "ignoring hidden '.goarc' file at $goarc_path\n" \
				    "\n Consider renaming the file to 'goarc' instead\n" }

			if {[file exists $goarc_path_candidate]} {

				set goarc_file_path [file join $goarc_path $goarc_name]

				#
				# Change to the directory of the goarc file before including it
				# so that the commands of the file are executed in the expected
				# directory.
				#
				cd $goarc_path
				safeinterp alias set config::_safe_set $goarc_file_path
				safeinterp invokehidden source $goarc_file_path
			}
		}

		interp delete safeinterp

		# revert original current working directory
		cd $project_dir
	}


	proc set_late_defaults {} {
		variable project_dir
		variable project_name
		variable common_var_dir
		variable versions_from_genode_dir
		variable license
		variable depot_user
		variable arch
		variable cross_dev_prefix
		variable ld_march
		variable cc_march
		variable run_as
		variable binary_name
		variable var_dir

		if {$versions_from_genode_dir == ""} { unset versions_from_genode_dir }
		if {$license                  == ""} { unset license }
		if {$depot_user               == ""} { unset depot_user }
		if {$arch                     == ""} { unset arch }
		if {$cross_dev_prefix         == ""} { unset cross_dev_prefix }
		if {$ld_march                 == ""} { unset ld_march }
		if {$cc_march                 == ""} { unset cc_march }
		if {$run_as                   == ""} { unset run_as }
		if {$binary_name              == ""} { unset binary_name }

		if {![info exists arch]} {
			switch [exec uname -m] {
			aarch64 { set arch "arm_v8a" }
			x86_64  { set arch "x86_64"  }
			default { exit_with_error "CPU architecture is not defined" }
			}
		}

		if {![info exists cross_dev_prefix]} {
			switch $arch {
			arm_v8a { set cross_dev_prefix "/usr/local/genode/tool/23.05/bin/genode-aarch64-" }
			x86_64  { set cross_dev_prefix "/usr/local/genode/tool/23.05/bin/genode-x86-"  }
			default { exit_with_error "tool-chain prefix is not defined" }
			}
		}

		if {![info exists ld_march]} {
			switch $arch {
			x86_64  { set ld_march "-melf_x86_64"  }
			default { set ld_march "" }
			}
		}

		if {![info exists cc_march]} {
			switch $arch {
			x86_64  { set cc_march "-m64"  }
			default { set cc_march "" }
			}
		}

		set var_dir [file join $project_dir var]
		if {$common_var_dir != ""} {
			set var_dir [file join $common_var_dir $project_name] }

		proc set_if_undefined { var_name value } {
			upvar ::config::$var_name var
			if {![info exists var] || $var == ""} {
				set var $value }
		}

		set_if_undefined depot_dir   [file join $var_dir depot]
		set_if_undefined public_dir  [file join $var_dir public]
		set_if_undefined contrib_dir [file join $var_dir contrib]
		set_if_undefined import_dir  [file join $var_dir import]
		set_if_undefined build_dir   [file join $var_dir build $arch]
		set_if_undefined abi_dir     [file join $var_dir abi   $arch]
		set_if_undefined bin_dir     [file join $var_dir bin   $arch]
		set_if_undefined dbg_dir     [file join $var_dir dbg   $arch]
		set_if_undefined run_dir     [file join $var_dir run]
		set_if_undefined api_dir     [file join $var_dir api]
	}

	# make namespace procs available as subcommands
	namespace ensemble create
}
