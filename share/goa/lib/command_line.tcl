#
# Determine verbosity level as evaluated by 'diag'
#
set verbose [consume_optional_cmdline_switch "--verbose"]


##
# Print version and exit
#
if {[consume_optional_cmdline_switch "--version"]} {
	puts [current_goa_branch]
	exit 0
}


#
# Handle -C argument, changing the current working directory
#
set original_dir [pwd]
set targeted_dir [consume_optional_cmdline_arg "-C" ""]
if {$targeted_dir != ""} {
	cd $targeted_dir }


#
# Search directory tree for project directories
#

proc goa_project_dirs { } {

	#
	# A project directory must contain an 'import' file, a 'src/' directory,
	# a 'pkg/' directory, a 'raw/' directory or an 'index' file. Don't consider
	# any directories behind a 'depot/', 'contrib/', 'build/', or 'var/'
	# directory.
	#
	set project_candidates [exec find -L -not -path "*/depot/*" \
	                             -and -not -path "*/contrib/*" \
	                             -and -not -path "*/build/*" \
	                             -and -not -path "*/var/*" \
	                             -and \( -name import \
	                                     -or -name src \
	                                     -or -name pkg \
	                                     -or -name raw \
	                                     -or -name index \)]

	regsub -line -all {(/(src|pkg|raw|import))$} $project_candidates "" project_candidates
	set project_candidates [lsort -unique $project_candidates]

	# filter out candidates that are do not look like a real project dir
	set project_dirs { }
	foreach dir $project_candidates {

		if {[looks_like_goa_project_dir $dir]} {
			lappend project_dirs $dir }
	}

	return $project_dirs
}


#
# If called with '-r' argument, scan current working directory for
# project directories and call goa for each project
#
if {[consume_optional_cmdline_switch "-r"]} {

	foreach dir [goa_project_dirs] {

		# assemble command for invoking the per-project execution of goa
		set cmd { }
		lappend cmd expect $argv0
		lappend cmd -C $dir

		if {$verbose} {
			lappend cmd --verbose }

		# append all unconsumed command line-arguments
		foreach arg $argv {
			lappend cmd $arg }

		if {[catch { exec -ignorestderr {*}$cmd >@ stdout }]} {
			exit 1 }
	}
	exit 0
}


#
# Goa was called without '-r' argument, process a single project directory
#

set project_dir [pwd]
set project_name [file tail $project_dir]

# defaults, potentially being overwritten by 'goarc' files
set arch                     ""
set cross_dev_prefix         ""
set rebuild                  0
set jobs                     1
set ld_march                 ""
set cc_march                 ""
set olevel                   "-O2"
set debug                    0
set versions_from_genode_dir ""
set common_var_dir           ""
set search_dir               ""
set depot_overwrite          0
set depot_retain             0
set license                  ""
set depot_user               ""
set run_as                   "genodelabs"
set target                   "linux"
set sculpt_version           ""
set cc_cxx_opt_std           "-std=gnu++20"
set binary_name              ""
array set target_opt {}

# if /proc/cpuinfo exists, use number of CPUs as 'jobs'
if {[file exists /proc/cpuinfo]} {
	catch {
		set num_cpus [exec grep "processor.*:" /proc/cpuinfo | wc -l]
		set jobs $num_cpus
		diag "use $jobs jobs according to /proc/cpuinfo"
	}
}


source $tool_dir/goarc

diag "process project '$project_name' with arguments: $argv"


#
# Read the hierarcy of 'goarc' files
#

set goarc_path_elements [file split $project_dir]
set goarc_name "goarc"
set goarc_path [file separator]


#
# The goarc file may contain paths relative to the local directory
# or relative to the home directory ('~' character). Convert those
# to absolute paths.
#
set path_var_names [list depot_dir public_dir cross_dev_prefix \
                         versions_from_genode_dir common_var_dir \
                         contrib_dir import_dir abi_dir build_dir \
                         run_dir bin_dir dbg_dir search_dir]


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

		source $goarc_file_path

		foreach var_name $path_var_names {

			if {![info exists $var_name]} {
				continue }

			set path [set $var_name]

			if {[llength $path] > 1} {
				exit_with_error "$goarc_file_path contains malformed" \
				                "definition of $var_name" }

			# de-reference home directory
			regsub {^~} $env(HOME) path

			# convert relative path to absolute path
			set path [file normalize $path]

			set $var_name $path
		}
	}
}

# revert original current working directory
cd $project_dir


#
# Override values with command-line arguments
#
# Change to the original PWD to resolve relative path names correctly.
#

foreach var_name $path_var_names {

	regsub -all {_} $var_name "-" tag_name

	set path [consume_optional_cmdline_arg "--$tag_name" ""]

	if {$path != ""} {
		set $var_name [file normalize $path] }
}

set jobs           [consume_optional_cmdline_arg "--jobs" $jobs]
set arch           [consume_optional_cmdline_arg "--arch" $arch]
set ld_march       [consume_optional_cmdline_arg "--ld-march" $ld_march]
set cc_march       [consume_optional_cmdline_arg "--cc-march" $cc_march]
set cc_cxx_opt_std [consume_optional_cmdline_arg "--cc-cxx-opt-std" $cc_cxx_opt_std]

#
# Define actions based on the primary command given at the command line
#

if {[llength $argv] == 0} {
	exit_with_error "missing command argument" }

set avail_commands [list update-goa archive-versions backtrace import diff build-dir \
                         build run run-dir export publish add-depot-user bump-version \
                         extract-abi-symbols help versions depot-dir]

foreach command $avail_commands {
	set perform($command) 0 }

# consume primary command from the command line
set command [lindex $argv 0]
set argv [lrange $argv 1 end]

if {[lsearch $avail_commands $command] == -1} {
	exit_with_error "unknown command '$command'" }

set perform($command) 1

##
# Enable 'dependency' action if 'action' is enabled
#
proc action_dependency { action dependency } {
	global perform
	if {$perform($action) == 1} {
		set perform($dependency) 1 } }

action_dependency publish         export
action_dependency export          build
action_dependency backtrace       run
action_dependency run             run-dir
action_dependency run-dir         build
action_dependency build           build-dir
action_dependency build-dir       depot-dir
action_dependency add-depot-user  depot-dir

if {[file exists import] && [file isfile import]} {
	action_dependency build-dir import }

#
# Read command-specific command-line arguments
#

if {$perform(update-goa)} {
	set args(switch_to_goa_branch) ""
	if {[llength $argv] == 1} {
		set args(switch_to_goa_branch) [lindex $argv 0]
		set argv [lrange $argv 1 end]
	}
}

if {$perform(backtrace)} {
	set binary_name      [consume_optional_cmdline_arg "--binary-name" ""]
	set with_backtrace 1
	set debug 1
}

if {$perform(help)} {
	set args(help_topic) overview
	if {[llength $argv] == 1} {
		set args(help_topic) [lindex $argv 0]
		set argv [lrange $argv 1 end]
	}
}

if {$perform(bump-version)} {
	set args(target_version) [clock format [clock seconds] -format %Y-%m-%d]
	if {[llength $argv] == 1} {
		set args(target_version) [lindex $argv 0]
		set argv [lrange $argv 1 end]
	}
}

if {$perform(add-depot-user)} {

	set args(depot_url)       [consume_optional_cmdline_arg    "--depot-url"   ""]
	set args(pubkey_file)     [consume_optional_cmdline_arg    "--pubkey-file" ""]
	set args(gpg_user_id)     [consume_optional_cmdline_arg    "--gpg-user-id" ""]
	set depot_overwrite [consume_optional_cmdline_switch "--depot-overwrite"]
	set depot_retain    [consume_optional_cmdline_switch "--depot-retain"]

	set hint ""
	append hint "\n Expected command:\n" \
	            "\n goa add-depot-user <name> --depot-url <url>" \
	            "\[--pubkey-file <file> | --gpg-user-id <id>\]\n"

	if {[llength $argv] == 0} {
		exit_with_error "missing user-name argument\n$hint" }

	if {[llength $argv] > 0} {
		set args(new_depot_user) [lindex $argv 0]
		set argv [lrange $argv 1 end]
	}

	if {$args(depot_url) == ""} {
		exit_with_error "missing argument '--depot-url <url>'\n$hint" }

	if {$args(pubkey_file) == "" && $args(gpg_user_id) == ""} {
		exit_with_error "public key of depot user $args(new_depot_user) not specified\n$hint" }

	if {$args(pubkey_file) != "" && $args(gpg_user_id) != ""} {
		exit_with_error "public key argument is ambigious\n" \
		                "\n You may either specify a pubkey file or a" \
		                "GPG user ID but not both.\n$hint" }

	if {$args(pubkey_file) != "" && ![file exists $args(pubkey_file)]} {
		exit_with_error "public-key file $args(pubkey_file) does not exist" }
}

# override 'rebuild' variable via optional command-line switch
if {$perform(build-dir)} {
	if {[consume_optional_cmdline_switch "--rebuild"]} {
		set rebuild 1 }
}

if {$perform(run-dir)} {
	set target [consume_optional_cmdline_arg "--target" $target]
	set run_as  [consume_optional_cmdline_arg "--run-as" $run_as]
	# unless given as additional argument, run the pkg named after the project
	set run_pkg [consume_optional_cmdline_arg "--pkg" $project_name]
}

if {$perform(build)} {
	if {[consume_optional_cmdline_switch "--warn-strict"   ]} { set warn_strict 1 }
	if {[consume_optional_cmdline_switch "--no-warn-strict"]} { set warn_strict 0 }

	if {[consume_optional_cmdline_switch "--with-backtrace"]} { set with_backtrace 1 }

	# override 'debug' variable via optional command-line switch
	if {[consume_optional_cmdline_switch "--debug"]} { set debug 1 }

	set olevel [consume_optional_cmdline_arg "--olevel" $olevel]
}

if {$perform(export)} {
	set depot_overwrite [consume_optional_cmdline_switch "--depot-overwrite"]
	set depot_retain    [consume_optional_cmdline_switch "--depot-retain"]
	set depot_user      [consume_optional_cmdline_arg "--depot-user"     $depot_user]
	set license         [consume_optional_cmdline_arg "--license"        $license]
	set publish_pkg     [consume_optional_cmdline_arg "--pkg"            ""]
	set sculpt_version  [consume_optional_cmdline_arg "--sculpt-version" $sculpt_version]
}

if {$perform(archive-versions)} {
	set depot_user [consume_optional_cmdline_arg "--depot-user" $depot_user] }

# consume target-specific arguments
consume_prefixed_cmdline_args "--target-opt-" target_opt

# consume package versions
consume_prefixed_cmdline_args "--version-" version

# back out if there is any unhandled argument
if {[llength $argv] > 0} {
	exit_with_error "invalid argument: [join $argv { }]" }

if {$search_dir               == ""} { set search_dir "$original_dir" }
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

	upvar default_$var_name default_var
	set default_var $value

	upvar $var_name var
	if {![info exists var]} {
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

##
# Return true if variable 'var_name' has not its default value
#
proc customized_variable { var_name } {
	global $var_name "default_$var_name"
	return [expr {[set $var_name] != [set "default_$var_name"]}]
}
