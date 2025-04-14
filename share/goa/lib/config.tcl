#
# goarc management
#

namespace eval ::config {
	namespace export path_var_names load_goarc_files set_late_defaults
	namespace export load_privileged_goarc_files
	namespace export default_cross_dev_prefix
	namespace export enable_safe_file_ops

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
	variable toolchain_version        ""
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
	variable install_dir              ""
	variable disable_sandbox          0
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


	# used as alias for 'lappend' in child interpreter
	proc _safe_lappend { rcfile safeinterp args } {
		global allowed_paths allowed_tools
		global privileged_rcfiles

		set nargs [llength $args]
		if {$nargs < 2} { return }

		set name  [lindex $args 0]
		set value [lindex $args 1]
		if {$name == "allowed_paths" || $name == "allowed_tools"} {
			if {[lsearch -exact $privileged_rcfiles [file dirname $rcfile]] < 0} {
				diag "variable '$name' may only be modified in a privileged goarc file"
				return
			}

			# de-reference home directory
			regsub {^~} $::env(HOME) value

			# convert relative path to absolute path
			set value [file normalize $value]

			lappend $name $value
		} elseif {[info exists ::config::[lindex [split $name "("] 0]]} {
			diag "cannot append to config variable '$name' in $rcfile"
			return
		} else {
			$safeinterp invokehidden lappend {*}$args
		}
	}


	proc _is_sub_directory { value paths } {

		foreach path $paths {
			if {[regexp "^$path" $value]} {
				return 1 }}

		return 0
	}


	# used as alias for 'file' in main interpreter
	proc _safe_file { args } {
		global allowed_paths allowed_tools writeable_paths
		global config::var_dir config::depot_dir config::public_dir config::project_dir

		proc _validate_path_arg { paths num args } {
			set target_path [lindex $args $num]
			if { $target_path == "" } { return }

			# normalize path and resolve all symlinks
			set normalized_path [unsafe_file normalize $target_path/___]
			set normalized_path [unsafe_file dirname $normalized_path]
			if {![_is_sub_directory $normalized_path $paths]} {
				exit_with_error "Command 'file $args' operates on an invalid path." \
				                "Valid paths are:\n" \
				                "\n [join $paths "\n "]" \
				                "\n\n You may consider setting 'allowed_paths' in" \
				                "your \$HOME/goarc or /goarc file."
			}
		}

		switch [lindex $args 0] {
			normalize   { _validate_path_arg $allowed_paths 1 {*}$args }
			executable  { if {![file exists [lindex $args 1]]} { return 0 }
			              _validate_path_arg $allowed_tools 1 {*}$args }
			link {
				set argnum 1
				set arg [lindex $args $argnum]
				if {$arg == "-hard" || $arg == "-symbolic"} { incr argnum }

				set writeable_paths [list $depot_dir $public_dir]
				if {[unsafe_file exists [unsafe_file join $project_dir import]]} {
					lappend writeable_paths [unsafe_file join $project_dir src]
					lappend writeable_paths [unsafe_file join $project_dir raw]
				}
				if {[info exists var_dir]} {
					lappend writeable_paths $var_dir }

				_validate_path_arg $writeable_paths $argnum {*}$args

				incr argnum
				if {[llength $args] > $argnum} {
					_validate_path_arg [concat $allowed_paths $allowed_tools] $argnum {*}$args }
			}
			fullnormalize {
				set path [lindex $args 1]
				set path [unsafe_file normalize $path/___]
				set path [unsafe_file dirname $path]
				_validate_path_arg $allowed_paths 0 $path
				return $path
			}

			split       -
			dirname     -
			tail        -
			copy        -
			delete      -
			mkdir       -
			attributes  -
			isfile      -
			isdirectory -
			exists      -
			type        -
			pathtype    -
			join        { }
			default {
				exit_with_error "Unknown command 'file $args'" }
		}

		interp invokehidden {} unsafe_file {*}$args
	}


	# used as alias for 'set' in child interpreter
	proc _safe_set { rcfile args } {
		global allowed_paths allowed_tools
		global privileged_rcfiles

		set nargs [llength $args]
		if {$nargs < 1} { return }

		set name [lindex $args 0]

		if {![info exists ::config::[lindex [split $name "("] 0]]} {
			diag "variable '$name' defined in $rcfile is not a config variable"
			return
		}

		if {$nargs == 1} {
			return [set ::config::$name] }

		if {$name == "disable_sandbox"} {
			if {[lsearch -exact $privileged_rcfiles [file dirname $rcfile]] < 0} {
				diag "variable '$name' may only be modified in a privileged goarc file"
				return
			}
		}

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

			set varname allowed_paths
			if {$name == "cross_dev_prefix"} {
				set varname allowed_tools }

			# check that path is a valid subdirectory
			if {![_is_sub_directory $value [set $varname]]} {
				exit_with_error "In $rcfile:" \
				                "\n Path variable '$name' set to '$value'" \
				                "\n defines an invalid path. Valid paths are:\n" \
				                "\n [join [set $varname] "\n "]" \
				                "\n\n You may consider setting '$varname' in" \
				                "your \$HOME/goarc or /goarc file."
			}
		}

		return [set ::config::$name $value]
	}


	proc load_goarc_files { { only_privileged_goarc 0 } } {
		global tool_dir original_dir config::project_dir
		global allowed_paths allowed_tools
		global privileged_rcfiles

		set allowed_paths [list [file normalize $project_dir] [file normalize $original_dir]]
		set allowed_paths [lsort -unique $allowed_paths]

		set allowed_tools [list /usr/]
		lappend allowed_tools $tool_dir

		# safe slave interpreter for goarc files
		interp create -safe safeinterp
		safeinterp hide set
		safeinterp hide lappend

		# load built-in goarc
		set rcfile [file join $tool_dir goarc]
		safeinterp alias set     config::_safe_set $rcfile
		safeinterp alias lappend config::_safe_lappend $rcfile safeinterp
		safeinterp invokehidden source $rcfile

		#
		# build list of privileged goarc files
		#
		lappend privileged_rcfiles [file normalize $::env(HOME)]
		lappend privileged_rcfiles [file normalize "/"]

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

				if {$only_privileged_goarc && [lsearch -exact $privileged_rcfiles $goarc_path] < 0} {
					continue }

				safeinterp alias set     config::_safe_set     $goarc_file_path
				safeinterp alias lappend config::_safe_lappend $goarc_file_path safeinterp
				safeinterp invokehidden source $goarc_file_path
			}
		}

		interp delete safeinterp

		# revert original current working directory
		cd $project_dir

	}


	proc enable_safe_file_ops {} {
		# hide file command and replace with safe version
		interp hide {} file unsafe_file
		interp alias {} file {} config::_safe_file
		interp alias {} unsafe_file {} interp invokehidden {} unsafe_file
	}


	proc load_privileged_goarc_files { } { load_goarc_files 1 }

	proc default_cross_dev_prefix { } {
		variable arch
		variable toolchain_version

		switch $arch {
		arm_v8a { return "/usr/local/genode/tool/$toolchain_version/bin/genode-aarch64-" }
		x86_64  { return "/usr/local/genode/tool/$toolchain_version/bin/genode-x86-"  }
		default { exit_with_error "unable to set tool-chain prefix for $arch" }
		}
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
		variable toolchain_version

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
			set cross_dev_prefix [default_cross_dev_prefix] }

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
		set_if_undefined install_dir [file join $var_dir install]
	}

	# make namespace procs available as subcommands
	namespace ensemble create
}
