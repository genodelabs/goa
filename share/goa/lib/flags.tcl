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


#
# C++-compiler flags
#
set cxxflags $cflags

if {[info exists warn_strict] && $warn_strict} {
	lappend cxxflags -Wextra -Weffc++ -Werror -Wsuggest-override }


#
# Linker flags
#
set ld_script_dir [file join $tool_dir ld]

set     ldflags { }
lappend ldflags -gc-sections
lappend ldflags -z max-page-size=0x1000
lappend ldflags -Ttext=0x01000000
lappend ldflags --eh-frame-hdr -rpath-link=.

if {$ld_march != ""} {
	lappend ldflags $ld_march }

# apply linker-argument prefix -Wl, to each flag
set prefixed_flags { }
foreach flag $ldflags {
	lappend prefixed_flags "-Wl,$flag" }
set ldflags $prefixed_flags


#
# Library arguments for the linker
#
set     ldlibs_common { }
lappend ldlibs_common -nostartfiles -nodefaultlibs -static-libgcc
lappend ldlibs_common -L$abi_dir

set     ldlibs_exe    { }
lappend ldlibs_exe   -Wl,--dynamic-linker=ld.lib.so
lappend ldlibs_exe    -T [file join $ld_script_dir genode_dyn.ld]

set     ldlibs_so     { }
lappend ldlibs_so     -Wl,-shared
lappend ldlibs_so     -l:ldso_so_support.lib.a
lappend ldlibs_so     -T [file join $ld_script_dir genode_rel.ld]

# determine ABIs to link against the executable
set abis { }
foreach api $used_apis {
	set symbol_files [glob -nocomplain -directory [file join $depot_dir $api lib symbols] *]
	foreach symbol_file $symbol_files {
		lappend abis [file tail $symbol_file] } }

source [file join $tool_dir lib util.tcl]

foreach abi $abis {
	set abi_name [archive_name $api]
	if {$abi_name != "ld" && $abi_name != "so"} {
		lappend ldlibs_exe "-l:$abi.lib.so"
		lappend ldlibs_so "-l:$abi.lib.so"
	}
}
