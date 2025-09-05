#
# Utility functions for node/attribute evaluation
# 
# Data format follows the same TCL-encoding used by the hrd tool.
# 

namespace eval node {

	namespace ensemble create

	namespace export empty-node valid
	namespace export type enabled attributes children
	namespace export attr-tag attr-value
	namespace export for-each-node for-all-nodes with-attribute default

	# a node is a list with 7 elements
	proc empty-node { } {
		return {} {} {} {} {} {} {} }

	proc type       { data } { return [lindex $data 0] }
	proc enabled    { data } { return [lindex $data 2] }
	proc attributes { data } { return [lindex $data 4] }
	proc children   { data } { return [lindex $data 5] }

	proc attr-tag   { data } { return [lindex $data 1] }
	proc attr-value { data } { return [lindex $data 2] }

	proc valid { data } {
		# TCL-encoded HRD node is a list with 7 elements
		if {[llength $data] == 7} {

			# node type must not contain spaces
			if {[llength [node type $data]] != 1} {
				return false }

			# attributes have length 3
			foreach attr [node attributes $data] {
				if {[llength $attr] != 3} {
					return false } }

			# children must be nodes as well
			foreach child [node children $data] {
				if {[llength $child] != 7} {
					return false } }

			return true
		}

		return false
	}
	
	##
	# execute body on every subnode of given type
	# 
	proc for-each-node { data type &node body } {
		upvar ${&node} node
		foreach node [node children $data] {
			if {[node type $node] == $type && [node enabled $node]} {
				uplevel 1 $body }
		}
	}

	##
	# execute body on every subnode
	#
	proc for-all-nodes { data &type &node body } {
		upvar ${&type} type
		upvar ${&node} node
		foreach node [node children $data] {
			if {[node enabled $node]} {
				set type [node type $node]
				uplevel 1 $body
			}
		}
	}

	proc default { body } { uplevel 1 $body }

	##
	# execute body on attribute value with given tag
	#
	# Note: returns error if the attribute is not present or (if provided)
	#       executes an alternative command (e.g. default)
	#
	# Example:
	#
	# with-attribute $data "unscoped_label" value {
	#   ...
	# } with-attribute $data "label" value {
	#   ...
	# } default {
	#   ...
	# }
	#
	proc with-attribute { data tag &value body args } {
		upvar ${&value} value

		set found 0
		foreach attr [node attributes $data] {
			if {[node attr-tag $attr] == $tag} {
				set value [node attr-value $attr]
				set found 1
				uplevel 1 $body
				break
			}
		}

		if {!$found} {
			if {[llength $args] > 0} {
				uplevel 1 node $args
			} else {
				return -code error -errorcode ATTRIBUTE_MISSING "Missing attribute $tag"
			}
		}
	}
}
