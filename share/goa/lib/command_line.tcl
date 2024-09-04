#
# Trace callback preventing write access to immutable variables
# Note: TCL 9.0 will supposedly support const variables.
#
proc const_var { n1 n2 op } {
	exit_with_error "Write access to const variable $n1" }

#
# Trace callback for sanitizing version information
#
proc version_var { n1 n2 op } {
	global config::version
	set value [string trim $version($n2)]
	set version($n2) $value
	if {[string first / $value] >= 0} {
		exit_with_error "Value of 'version($n2)' must not contain slashes" }
}

#
# Determine verbosity level as evaluated by 'diag'
#
set verbose [consume_optional_cmdline_switch "--verbose"]
trace add variable verbose write const_var

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
unset targeted_dir

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

source [file join $tool_dir lib config.tcl]

diag "process project '$config::project_name' with arguments: $argv"

config load_goarc_files

#
# Override values with command-line arguments
#
# Change to the original PWD to resolve relative path names correctly.
#
foreach var_name [config path_var_names] {

	set var_name [lindex [split $var_name :] end]
	regsub -all {_} $var_name "-" tag_name

	set path [consume_optional_cmdline_arg "--$tag_name" ""]

	if {$path != ""} {
		set config::$var_name [file normalize $path] }
}

namespace eval config {
	set jobs           [consume_optional_cmdline_arg "--jobs" $jobs]
	set arch           [consume_optional_cmdline_arg "--arch" $arch]
	set ld_march       [consume_optional_cmdline_arg "--ld-march" $ld_march]
	set cc_march       [consume_optional_cmdline_arg "--cc-march" $cc_march]
	set cc_cxx_opt_std [consume_optional_cmdline_arg "--cc-cxx-opt-std" $cc_cxx_opt_std]
}

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
	set config::binary_name [consume_optional_cmdline_arg "--binary-name" ""]
	set config::with_backtrace 1
	set config::debug 1
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

	set args(depot_url)         [consume_optional_cmdline_arg    "--depot-url"   ""]
	set args(pubkey_file)       [consume_optional_cmdline_arg    "--pubkey-file" ""]
	set args(gpg_user_id)       [consume_optional_cmdline_arg    "--gpg-user-id" ""]
	set config::depot_overwrite [consume_optional_cmdline_switch "--depot-overwrite"]
	set config::depot_retain    [consume_optional_cmdline_switch "--depot-retain"]

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
		set config::rebuild 1 }
}

if {$perform(run-dir)} {
	set config::target [consume_optional_cmdline_arg "--target" $config::target]
	set config::run_as [consume_optional_cmdline_arg "--run-as" $config::run_as]
	# unless given as additional argument, run the pkg named after the project
	set args(run_pkg)  [consume_optional_cmdline_arg "--pkg"    $config::project_name]
}

if {$perform(build)} {
	if {[consume_optional_cmdline_switch "--warn-strict"   ]} { set config::warn_strict 1 }
	if {[consume_optional_cmdline_switch "--no-warn-strict"]} { set config::warn_strict 0 }

	if {[consume_optional_cmdline_switch "--with-backtrace"]} { set config::with_backtrace 1 }

	# override 'debug' variable via optional command-line switch
	if {[consume_optional_cmdline_switch "--debug"]}          { set config::debug 1 }

	set config::olevel [consume_optional_cmdline_arg "--olevel" $config::olevel]
}

if {$perform(export)} {
	set config::depot_overwrite [consume_optional_cmdline_switch "--depot-overwrite"]
	set config::depot_retain    [consume_optional_cmdline_switch "--depot-retain"]
	set config::depot_user      [consume_optional_cmdline_arg "--depot-user"     $config::depot_user]
	set config::license         [consume_optional_cmdline_arg "--license"        $config::license]
	set config::sculpt_version  [consume_optional_cmdline_arg "--sculpt-version" $config::sculpt_version]
	set args(publish_pkg)       [consume_optional_cmdline_arg "--pkg"            ""]
}

if {$perform(archive-versions)} {
	set config::depot_user [consume_optional_cmdline_arg "--depot-user" $config::depot_user] }

# consume target-specific arguments
consume_prefixed_cmdline_args "--target-opt-" config::target_opt

# consume package versions
consume_prefixed_cmdline_args "--version-" config::version

# back out if there is any unhandled argument
if {[llength $argv] > 0} {
	exit_with_error "invalid argument: [join $argv { }]" }

config set_late_defaults

unset original_dir

# make all variables (except version array) in config namespace immutable
foreach var [info vars ::config::*] {
	if {$var == "::config::version"} {
		trace add variable $var write version_var
	} else {
		trace add variable $var write const_var
	}
}

