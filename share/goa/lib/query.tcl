#
# XML/HRD query procedures
#
# For all procedures, input data can be a file, a node object or an HRD object.
# 

namespace eval query {

	namespace ensemble create
	namespace export validate-syntax
	namespace export attributes attribute optional-attribute
	namespace export node optional-node

	proc validate-syntax { data } {
		try {
			hrd tool $data format
		} trap CHILDSTATUS { } {
			exit_with_error "invalid syntax in $data"
		} on error { msg } { error $msg $::errorInfo }
	}

	##
	# query 'data' for attributes described by 'path'
	# 
	# returns list of attributes (may be empty)
	proc attributes { data path } {
		try {
			return [split [hrd tool $data get $path] "\n"]
		} trap CHILDSTATUS { msg } {
			exit_with_error "unable to get '$path' from $data:\n $msg"
		} on error { msg } { error $msg $::errorInfo }
	}

	##
	# query 'data' for the first attribute matching 'path'
	# 
	# returns attribute value or errorcode ATTRIBUTE_MISSING
	proc attribute { data path } {
		set result [attributes $data $path]
		if {[llength $result] == 0} {
			return -code error -errorcode ATTRIBUTE_MISSING "No attribute '$path' in $data" }

		return [lindex $result 0]
	}

	##
	# query 'data' for the first attribute matching 'path'
	# 
	# returns 'default' if attribute is missing
	proc optional-attribute { data path default } {
		try {
			return [attribute $data $path]
		} trap ATTRIBUTE_MISSING { } {
			return default
		} on error { msg } { error $msg $::errorInfo }
	}

	##
	# query 'data' for the first subnode matching 'path'
	# 
	# returns node object or errorcode NODE_MISSING
	proc node { data path } {
		try {
			set query  [split [hrd tool $data --output-tcl subnodes $path] "\n"]
			if {[llength $query] == 0} {
				return -code error -errorcode NODE_MISSING "No node '$path' in $data" } 

			set result [lindex $query 0]
			if {![::node enabled $result]} {
				exit_with_error "subnode '$path' from $data is disabled"
			}
			return $result
			
		} trap CHILDSTATUS { msg } {
			exit_with_error "unable to get subnodes '$path' from $data:\n $msg"

		} on error { msg } { error $msg $::errorInfo }
	}

	##
	# query 'data' for the first subnode matching 'path'
	#
	# returns node object (may be empty)
	proc optional-node { data path } {
		try {
			return [query node $data $path]
		 } trap NODE_MISSING { } {
			return [::node empty-node]
		} on error { msg } { error $msg $::errorInfo }
	}
}
