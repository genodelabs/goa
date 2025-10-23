#!/usr/bin/env tclsh

#
# Search for modules given on command-line in abi directory  and create log file
# reporting if apis are present. Always report success (exit 0).
#
# This script is called from Meson, it does not work when started manually
#


proc _consume_cmdline_switches { pattern } {
	global argv

	# find argument name in argv list
	set tag_idx_list [lsearch -all $argv $pattern]

	if {[llength $tag_idx_list] == 0} {
		return 0 }

	# prune argv
	set tag_idx_list [lreverse $tag_idx_list]
	foreach tag_idx $tag_idx_list {
		set argv [lreplace $argv $tag_idx $tag_idx]
	}

	return 1
}


#
# Main
#

# tool_dir is our location with 'lib' removed
set tool_dir [file join [file dirname $argv0] ../]

source [file join $tool_dir lib util.tcl]

# print version and exit
if {[consume_optional_cmdline_switch --version]} {
	puts stdout "2.2.0"
	exit 0
}

# remove all options from argv. Add specific options as needed above
_consume_cmdline_switches "-*"

# PKG_CONFIG_LIBDIR is set in cross file via 'pkg_config_libdir' in [properties]
set build_dir      $env(PKG_CONFIG_LIBDIR)
set abi_dir        [file join $build_dir abi]
set abis           [glob -tails -directory $abi_dir -nocomplain *.lib.so]
set pkg_config_log [file join $build_dir "pkg-config.log"]
set modules        $argv

set fh [open $pkg_config_log "WRONLY APPEND"]

foreach module $modules {
	set found [expr {[lsearch -nocase -exact $abis "$module.lib.so"] > -1}]
	puts $fh "$module:$found"
}

close $fh

# always return without error (= module found)
exit 0
