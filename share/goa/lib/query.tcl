#
# XML/HRD query procedures
# 

##
# Check syntax of specified XML file using xmllint
#
proc check_xml_syntax { xml_file } {

	try {
		exec xmllint -noout $xml_file

	} trap CHILDSTATUS {result} {
		exit_with_error "invalid XML syntax in $xml_file:\n$result"

	} on error {msg} { error $msg $::errorInfo }
}


proc query_from_string { xpath node default_value } {

	set content [exec xmllint --xpath $xpath - << $node]

	if {$content == ""} {
		set content $default_value }

	return $content
}


proc query_attrs_from_string { node_path attr_name xml }  {

	set xpath "$node_path/attribute::$attr_name"
	set attributes [exec xmllint --xpath $xpath - << $xml]

	set values { }
	foreach attr $attributes {
		regexp {"(.*)"} $attr dummy value
		lappend values $value
	}
	return $values
}


proc query_attrs_from_file { node_path attr_name xml_file }  {

	set xpath "$node_path/attribute::$attr_name"

	set attributes { }
	catch {
		set attributes [exec xmllint --xpath $xpath $xml_file] }

	set values { }
	foreach attr $attributes {
		regexp {"(.*)"} $attr dummy value
		lappend values $value
	}
	return $values
}


proc query_attr_from_file { node_path attr_name xml_file }  {

	set xpath "$node_path/attribute::$attr_name"
	set attr_value [exec xmllint --xpath $xpath $xml_file]

	# in the presence of multiple matching xpaths, return only the first
	regexp {"(.*)"} [lindex $attr_value 0] dummy value
	return $value
}


proc query_from_file { node_path xml_file }  {

	set xpath "$node_path"
	set content [exec xmllint --format --xpath $xpath $xml_file]

	return $content
}


proc query_raw_from_file { node_path xml_file }  {

	set xpath "$node_path"
	set content [exec xmllint --xpath $xpath $xml_file]

	return $content
}


proc desanitize_xml_characters { string } {
	regsub -all {&gt;} $string {>} string
	regsub -all {&lt;} $string {<} string
	return $string
}


proc try_query_attr_from_file { runtime_file attr } {
	if {[catch {
		set result [query_attr_from_file /runtime $attr $runtime_file]
	}]} {
		exit_with_error "missing '$attr' attribute in <runtime> at $runtime_file"
	}
	return $result
}
