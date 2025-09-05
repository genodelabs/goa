#
# HRD utility functions (hrd-tool, formatting and generation)
#
# Note: HRD data is stored as a list starting with the keyword "HRD". Each
#       element represents a single line of HRD.
# Note: The HRD tool also accepts node objects (see node.tcl).
# 

namespace eval hrd {

	namespace ensemble create
	namespace export tool
	namespace export format-xml format as_string
	namespace export valid empty first
	namespace export create append indent

	# detect format of file
	proc _detect_format { file } {
		set fd [open $file]
		gets $fd line
		close $fd

		if {[regexp {^\<.*} $line]} {
			return "xml" }

		return "hrd"
	}

	# helper for printing HRD and Node data
	proc as_string { input } {
		if {[node valid $input]} {
			return $input
		} elseif {[valid $input]} {
			lappend input "-"
			return [join [_raw $input] "\n"]
		}

		exit_with_error "Input data must be valid HRD or Node '$input'."
	}

	#####################################
	# HRD tool execution and formatting #
	#####################################

	# executes hrd tool on 'input' (file path or input data)
	proc tool { input args } {
		global tool_dir

		set cmd [file join $tool_dir hrd]

		if {[file exists $input]} {
			if {[_detect_format $input] == "xml"} {
				lappend cmd --import-xml }
		} else {
			set cmd [list echo "[as_string $input]" | {*}$cmd]

			if {[node valid $input]} {
				lappend cmd --import-tcl
			}

			set input "-"
		}

		# diag "Executing: " {*}$cmd {*}$args $input

		exec {*}$cmd {*}$args $input
	}

	# format 'input' to XML
	proc format-xml { input } {
		if {$input == [node empty-node] || [empty $input]} {
			return [list] }

		try {
			return [split [tool $input --output-xml format] "\n"]

		} trap CHILDSTATUS { msg } {
			exit_with_error "unable to format '[as_string $input]' to XML:\n $msg"
		} on error { msg } { error $msg $::errorInfo }
	}

	# format 'input' into HRD and strip '-' terminator
	proc format { input } {
		if {$input == [node empty-node] || [empty $input]} {
			return [hrd create] }

		try {
			return [list HRD {*}[lrange [split [tool $input format] "\n"] 0 end-1]]

		} trap CHILDSTATUS { msg } {
			exit_with_error "unable to format '[as_string $input]' to HRD:\n $msg"
		} on error { msg } { error $msg $::errorInfo }
	}

	#######################
	# HRD data generation #
	#######################

	# add "+" to the first line if not present
	proc _make_child { &hrd } {
		upvar ${&hrd} hrd

		_fail_invalid $hrd "_make_child failed"

		if {[empty $hrd]} { return }

		set first [lindex $hrd 1]
		if {![regexp {^\s*\+} $first]} {
			set hrd [lmap line $hrd {
				if {$line == "HRD"} {
					set line }
				string cat "  " $line
			}]
			lset hrd 1 [string cat "+ " $first]
		}
	}

	# exit if 'arg' is not an HRD object
	proc _fail_invalid { arg msg } {
		if {![hrd valid $arg]} {
			exit_with_error "$msg: Argument '$arg' is invalid HRD data" }
	}

	# return list without the leading HRD keyword
	proc _raw { hrd } {
		return [lrange $hrd 1 end] }

	##
	# Check whether 'data' is an HRD object
	# 
	proc valid { data } {
		if {[lindex $data 0] == "HRD"} {
			return true }

		return false
	}

	##
	# Check whether 'data' is either an empty list or an empty HRD object
	# 
	proc empty { data } {
		set first [lindex $data 0]
		if {$first == "HRD"} {
			set first [lindex $data 1] }

		if {[llength $first] == 0} {
			return true
		}

		return false
	}

	##
	# Return first line
	#
	proc first { hrd } {
		_fail_invalid $hrd "HRD first failed"
		return [lindex $hrd 1]
	}

	##
	# create HRD object
	# 
	proc create { args } {
		set result [list HRD]
		hrd append result {*}$args
		return $result
	}

	##
	# append data to HRD object
	# 
	proc append { &hrd args } {
		upvar ${&hrd} hrd

		_fail_invalid $hrd "HRD append failed"

		foreach arg $args {
			if {[empty $arg]} { continue }

			if {[valid $arg]} {
				_make_child arg
				lappend hrd {*}[_raw $arg]
			} else {
				lappend hrd $arg
			}
		}
	}

	##
	# Indent HRD data by 'level' indentation levels
	# 
	proc indent { level hrd } {
		_fail_invalid $hrd "HRD indent failed"

		_make_child hrd

		set indentation [string repeat "  " $level]
		set data [hrd create]
		foreach line [_raw $hrd] {
			lappend data [string cat $indentation $line]
		}

		return $data
	}
}
