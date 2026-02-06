#
# HID utility functions (hid-tool, formatting and generation)
#
# Note: HID data is stored as a list starting with the keyword "HID". Each
#       element represents a single line of HID.
# Note: The HID tool also accepts node objects (see node.tcl).
# 

namespace eval hid {

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

		return "hid"
	}

	# helper for printing HID and Node data
	proc as_string { input } {
		if {[node valid $input]} {
			return $input
		} elseif {[valid $input]} {
			lappend input "-"
			return [join [_raw $input] "\n"]
		}

		exit_with_error "Input data must be valid HID or Node '$input'."
	}

	#####################################
	# HID tool execution and formatting #
	#####################################

	# executes hid tool on 'input' (file path or input data)
	proc tool { input args } {
		global tool_dir

		set cmd [file join $tool_dir hid]

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

		# open as pipe to catch stderr separately
		set f [open "| [list {*}$cmd {*}$args $input]"]
		set output [string trimright [read $f]]
		try {
			close $f
		} trap NONE { msg } {
			# written to stderr but exited with 0
		}

		return $output
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

	# format 'input' into HID and strip '-' terminator
	proc format { input } {
		if {$input == [node empty-node] || [empty $input]} {
			return [hid create] }

		try {
			return [list HID {*}[lrange [split [tool $input format] "\n"] 0 end-1]]

		} trap CHILDSTATUS { msg } {
			exit_with_error "unable to format '[as_string $input]' to HID:\n $msg"
		} on error { msg } { error $msg $::errorInfo }
	}

	#######################
	# HID data generation #
	#######################

	# add "+" to the first line if not present
	proc _make_child { &hid } {
		upvar ${&hid} hid

		_fail_invalid $hid "_make_child failed"

		if {[empty $hid]} { return }

		set first [lindex $hid 1]
		if {![regexp {^\s*\+} $first]} {
			set hid [lmap line $hid {
				if {$line == "HID"} {
					set line }
				string cat "  " $line
			}]
			lset hid 1 [string cat "+ " $first]
		}
	}

	# exit if 'arg' is not an HID object
	proc _fail_invalid { arg msg } {
		if {![hid valid $arg]} {
			exit_with_error "$msg: Argument '$arg' is invalid HID data" }
	}

	# return list without the leading HID keyword
	proc _raw { hid } {
		return [lrange $hid 1 end] }

	##
	# Check whether 'data' is an HID object
	# 
	proc valid { data } {
		if {[lindex $data 0] == "HID"} {
			return true }

		return false
	}

	##
	# Check whether 'data' is either an empty list or an empty HID object
	# 
	proc empty { data } {
		set first [lindex $data 0]
		if {$first == "HID"} {
			set first [lindex $data 1] }

		if {[llength $first] == 0} {
			return true
		}

		return false
	}

	##
	# Return first line
	#
	proc first { hid } {
		_fail_invalid $hid "HID first failed"
		return [lindex $hid 1]
	}

	##
	# create HID object
	# 
	proc create { args } {
		set result [list HID]
		hid append result {*}$args
		return $result
	}

	##
	# append data to HID object
	# 
	proc append { &hid args } {
		upvar ${&hid} hid

		_fail_invalid $hid "HID append failed"

		foreach arg $args {
			if {[empty $arg]} { continue }

			if {[valid $arg]} {
				_make_child arg
				lappend hid {*}[_raw $arg]
			} else {
				lappend hid $arg
			}
		}
	}

	##
	# Indent HID data by 'level' indentation levels
	# 
	proc indent { level hid } {
		_fail_invalid $hid "HID indent failed"

		_make_child hid

		set indentation [string repeat "  " $level]
		set data [hid create]
		foreach line [_raw $hid] {
			lappend data [string cat $indentation $line]
		}

		return $data
	}
}
