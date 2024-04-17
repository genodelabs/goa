#
# CPP flags
#
set include_dirs { }
foreach api $used_apis {
	set dir [file join $depot_dir $api include]

	if {$arch == "x86_64"} {
		lappend include_dirs [file join $dir spec x86_64]
		lappend include_dirs [file join $dir spec x86]
	}
	if {$arch == "arm_v8a"} {
		lappend include_dirs [file join $dir spec arm_64]
	}
	lappend include_dirs [file join $dir spec 64bit]
	lappend include_dirs $dir
}

set libgcc_path    [file normalize [eval "exec $cross_dev_prefix\gcc -print-libgcc-file-name"]]
set libgcc_include [file join [file dirname $libgcc_path] include]

lappend include_dirs [file normalize $libgcc_include]

set cppflags { }
lappend cppflags "-nostdinc"

#
# The 'cppflags' variable is extended with the include paths after 'quirks.tcl'
# is processed.
#


#
# C-compiler flags
#
set cflags { }
lappend cflags -fPIC
lappend cflags $olevel
lappend cflags -D__GENODE__

if {$cc_march != ""} {
	lappend cflags $cc_march }

if {[info exists warn_strict] && $warn_strict} {
	lappend cflags -Wall }

if {$debug} {
	lappend cflags -g }


#
# C++-compiler flags
#
set cxxflags $cflags
lappend cxxflags $cc_cxx_opt_std

if {[info exists warn_strict] && $warn_strict} {
	lappend cxxflags -Wextra -Weffc++ -Werror -Wsuggest-override }


#
# Linker flags
#
set ld_script_dir [file join $tool_dir ld]

set     ldflags { }
lappend ldflags -gc-sections
lappend ldflags -z max-page-size=0x1000
lappend ldflags --eh-frame-hdr -rpath-link=.

if {$ld_march != ""} {
	lappend ldflags $ld_march }

# apply linker-argument prefix -Wl, to each flag
set prefixed_flags { }
foreach flag $ldflags {
	lappend prefixed_flags "-Wl,$flag" }
set ldflags $prefixed_flags

# set -Ttext flag only for executables
set ldflags_so [list {*}$ldflags]
lappend ldflags -Wl,-Ttext=0x01000000


#
# Library arguments for the linker
#
set     ldlibs_common { }
lappend ldlibs_common -nostartfiles -nodefaultlibs -lgcc
lappend ldlibs_common -L$abi_dir

set     ldlibs_exe    { }
lappend ldlibs_exe   -Wl,--dynamic-linker=ld.lib.so
#
# this is neeed so "main", "Component::construct" are dynamic symbols
# and ld.lib.so can find them
#
lappend ldlibs_exe    -Wl,--dynamic-list=[file join $ld_script_dir genode_dyn.dl]
lappend ldlibs_exe    -T [file join $ld_script_dir genode_dyn.ld]

set     ldlibs_so     { }
lappend ldlibs_so     -Wl,-shared
lappend ldlibs_so     -Wl,--whole-archive -Wl,-l:ldso_so_support.lib.a -Wl,--no-whole-archive
lappend ldlibs_so     -T [file join $ld_script_dir genode_rel.ld]

# determine ABIs to link against the executable
set abis { }
foreach api $used_apis {
	set symbol_files [glob -nocomplain -directory [file join $depot_dir $api lib symbols] *]
	foreach symbol_file $symbol_files {
		lappend abis [file tail $symbol_file] } }

foreach abi $abis {
	if {$abi != "so"} {
		lappend ldlibs_exe "-l:$abi.lib.so"
	}
	if {$abi != "ld" && $abi != "so"} {
		lappend ldlibs_so "-l:$abi.lib.so"
	}
}
