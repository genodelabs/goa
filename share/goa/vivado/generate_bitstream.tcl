proc findProject { } {
	set files [glob -nocomplain [file join * *.xpr]]
	foreach file $files { return $file }

	puts "ERROR: Could not find project file (.xpr) in build directory '[pwd]'\n"
	return ""
}

set target "fpga.bit"

set jobs "1"
if { $::argc > 0 } {
	for {set i 0} {$i < $::argc} {incr i} {
		set option [string trim [lindex $::argv $i]]
		switch -regexp -- $option {
			"--jobs"         { incr i; set jobs   [lindex $::argv $i] }
			"--target"       { incr i; set target [lindex $::argv $i] }
		default {
			if { [regexp {^-} $option] } {
				puts "ERROR: Unknown option '$option' specified.\n"
				return 1
			}
		}}
	}
}

# find project file
set project_file [findProject]
if {![file exists $project_file]} { return 1 }

open_project $project_file

set runs [list "synth_1" "impl_1"]
# find runs
if {[string equal [get_runs -quiet $runs] ""]} {
	puts "ERROR: Runs '$runs' not found.\n"
	return 1
}

foreach run $runs { reset_run $run }
set last_run [lindex $runs [llength $runs]-1]

puts "Generating bitstream"
launch_runs $last_run -jobs $jobs -quiet -to_step write_bitstream

while { [get_property PROGRESS [get_runs $last_run]] != "100%" } {
	set error 0

	# print status
	foreach run [get_runs] status [get_property STATUS [get_runs]] progress [get_property PROGRESS [get_runs]] {
		puts "$progress\t - $run\t - $status"
		if {[regexp "ERROR" $status]} { set error 1 }
	}

	if { $error } { return 1}
	wait_on_run $last_run -timeout 1
}

# export hardware platform (including bitstream)
set xsa_file [file rootname $target].xsa
open_impl_design $last_run
write_hw_platform -fixed -force -include_bit $xsa_file
close_project

# extract bitstream
exec unzip $xsa_file *.bit

exit 0
