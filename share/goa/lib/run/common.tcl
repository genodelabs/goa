##
##
# Find a particular ROM in depot archives. Returns the file path if found.
# Otherwise it returns an empty string.
#
proc _find_rom_in_archives { rom_name binary_archives } {
	global config::depot_dir

	foreach archive $binary_archives {
		set file_path [file join $depot_dir $archive $rom_name]
		if {[file exists $file_path]} {
			return $file_path }
	}

	return ""
}


##
##
# Acquire config
#
proc _acquire_config { runtime_file runtime_archives } {

	set routes [hrd create]
	set config [query optional-node $runtime_file "runtime | + config"]

	try {
		set rom_name [query attribute $runtime_file "runtime | : config"]
		hrd append routes "+ service ROM | label: config | + parent | label: $rom_name"

		if {[node type $config] == "config"} {
			exit_with_error "runtime config is ambiguous,"
			                "specified as 'config' attribute as well as 'config' node" }

		# check existence of $rom_name in raw/
		set config_file [file join raw $rom_name]
		if {![file exists $config_file]} {
			set binary_archives [binary_archives [apply_versions $runtime_archives]]
			set config_file [_find_rom_in_archives $rom_name $binary_archives]

			if {$config_file == ""} {
				exit_with_error "runtime declares 'config: $rom_name' but the file raw/$rom_name is missing" }
		}

		# load content into config variable
		set config [query node $config_file "config"]
	} trap ATTRIBUTE_MISSING { } {
		# no config attribute
	} trap NODE_MISSING { } {
		# missing config node in config file
		exit_with_error "missing config node in referenced rom module $config_file"
	} on error { msg } { error $msg $::errorInfo }

	if {[node type $config] != "config"} {
		exit_with_error "runtime lacks a configuration\n" \
		                "\n You may declare a 'config' attribute for the 'runtime' node, or" \
		                "\n define a 'config' node inside the 'runtime' node.\n"
	}
	return [list $config $routes]
}


##
##
# Check consistency between config of init component and required/provided
# runtime services
#
proc _validate_init_config { config &required_services &provided_services } {
	upvar 1 ${&required_services} required_services
	upvar 1 ${&provided_services} provided_services

	# get services from 'parent-provides' node
	set parent_provides [query attributes $config "config | + parent-provides | + service | : name"]
	set parent_provides [string tolower $parent_provides]

	# check that all required services are mentioned as 'parent-provides'
	foreach service_name [array names required_services] {
		if {[lsearch -exact $parent_provides $service_name] == -1} {
			exit_with_error "runtime requires '$service_name', which is not mentioned in 'parent-provides'" }
	}

	# check that all parent_provides services are base services or required services
	foreach parent_service $parent_provides {
		if {[lsearch -exact [list rom pd cpu log rm] $parent_service] > -1} { continue }

		if {[lsearch -nocase [array names required_services] $parent_service] == -1} {
			log "config 'parent-provides' mentions a $parent_service service;" \
			    "consider adding '$parent_service' as a required runtime service"
		}
	}

	# get services from config
	set services_from_config [query attributes $config "config | + service | : name"]
	set services_from_config [lsort -unique [string tolower $services_from_config]]

	# check that provided service is mentioned in config
	set checked_provided_services { }
	foreach service_name [array names provided_services] {
		if {[lsearch -exact $services_from_config $service_name] == -1} {
			exit_with_error "runtime provides '$service_name' but the corresponding" \
			                "service routing is missing in config"
		} else {
			lappend checked_provided_services $service_name
		}
	}

	# check that services mentioned/routed in config are provided
	foreach service $services_from_config {
		if {[lsearch -exact $checked_provided_services $service] == -1} {
			exit_with_error "runtime does not provide '$service' as indicated by config" }
	}
}


##
##
# Acquire list of required and provided services (as node objects)
# This procedure also conducts a couple of sanity checks on the way.
#
proc _acquire_services { known_services runtime_file config } {
	# get required services from runtime file
	array set required_services { }

	set data [query optional-node $runtime_file "runtime | + requires"]
	node for-all-nodes $data type node {
		if {![info exists required_services($type)]} {
			set required_services($type) { } }

		lappend required_services($type) $node
	}

	# check that all required services are known
	foreach service_name [array names required_services] {
		if {[lsearch -exact $known_services $service_name] == -1} {
			exit_with_error "runtime requires unknown '$service_name'" }
	}

	# get provided services from runtime file
	array set provided_services { }
	set data [query optional-node $runtime_file "runtime | + provides"]
	node for-all-nodes $data type node {
		if {![info exists provided_services($type)]} {
			set provided_services($type) { } }

		lappend provided_services($type) $node
	}

	# check that all provided services are known
	foreach service_name [array names provided_services] {
		if {[lsearch -exact $known_services $service_name] == -1} {
			exit_with_error "runtime provides unknown '$service_name'" }
	}

	try {
		# if 'parent-provides' is present in config, do more consistency checks
		query node $config "config | + parent-provides"
		_validate_init_config $config required_services provided_services
	} trap NODE_MISSING { } {
	} on error { msg } { error $msg $::errorInfo }

	return [list [array get required_services] [array get provided_services]]
}


##
##
# Generate and install runtime config.
# The procedure may extend the lists of 'runtime_archives' and 'rom_modules'.
#
proc generate_runtime_config { runtime_file &runtime_archives &rom_modules } {
	upvar 1 ${&runtime_archives} runtime_archives
	upvar 1 ${&rom_modules} rom_modules

	global args config::run_dir config::var_dir config::run_as config::bin_dir

	try {
		set ram    [query attribute $runtime_file "runtime | : ram"]
		set caps   [query attribute $runtime_file "runtime | : caps"]
		set binary [query attribute $runtime_file "runtime | : binary"]
	} on error { msg } { exit_with_error $msg }

	# get config (as node object) from runtime file
	lassign [_acquire_config $runtime_file $runtime_archives] config config_route

	# list of services that are do not need to mentioned as requirement
	set base_services   [list CPU PD LOG RM]

	# remaining services
	set other_services [list Audio_in Audio_out Uplink Nic Capture Event Gui TRACE \
	                         Block Platform IO_MEM IO_PORT IRQ File_system Timer \
	                         Rtc Gpu Report ROM Usb Terminal VM Pin_ctrl Pin_state \
	                         Play Record]

	# all known services
	set known_services [concat $base_services $other_services]

	# services supported by black_hole component
	set blackhole_supported_services [list report audio_in audio_out event \
	                                       capture gpu usb uplink play record]

	# check and acquire required/provided services from runtime file
	lassign [_acquire_services [string tolower $known_services] \
	                           $runtime_file $config] required provided

	array set required_services $required
	array set provided_services $provided

	# warn if base services are mentioned as requirements
	foreach service_name [array names required_services] {
		if {[lsearch -exact -nocase $base_services $service_name] > -1} {
			log "runtime explicitly requires '$service_name', which is always routed" }
	}

	# assemble list of rom modules from project's runtime file and all runtime
	# files in the referenced pkg archives
	set rom_modules [query attributes $runtime_file "runtime | + content | + rom | : label"]
	foreach runtime_file [runtime_files [apply_versions $runtime_archives]] {
		lappend rom_modules {*}[query attributes $runtime_file "runtime | + content | + rom | : label"]
	}

	set default_rom_modules [list core ld.lib.so init]

	# check presence of binary in rom_modules or default_rom_modules
	if {[lsearch -exact $rom_modules $binary] < 0 &&
		 [lsearch -exact $default_rom_modules $binary] < 0} {
		exit_with_error "Binary '$binary' not mentioned as content ROM module. \n" \
		                "\n You either need to add 'rom label: \"$binary\"' to the content ROM list" \
		                "\n or add a pkg archive to the 'archives' file from which to inherit."
	}

	# check availability of content ROM modules
	set binary_archives [binary_archives [apply_versions $runtime_archives]]
	foreach rom $rom_modules {
		# default content?
		if {[lsearch -exact $default_rom_modules $rom] > -1} {
			continue }

		# raw content?
		if {[file exists [file join raw $rom]]} {
			continue }

		# artifact?
		if {[file exists [file join $bin_dir $rom]]} {
			continue }

		# find in other archives
		if {[_find_rom_in_archives $rom $binary_archives] == ""} {
			exit_with_error "Unable to find content ROM module '$rom'.\n" \
			                "\n You either need to add it to the 'raw/' directory" \
			                "\n or add the corresponding dependency to the 'archives' file." }
	}

	lappend rom_modules {*}$default_rom_modules

	set start_nodes [hrd create]
	set provides    [hrd create]
	set routes      [hrd create]

	# add provided services
	foreach service_name [array names provided_services] {
		set cased_name [lindex $known_services [lsearch -exact -nocase $known_services $service_name]]
		hrd append provides "+ service $cased_name"
	}

	# bind provided services
	set _res [bind_provided_services provided_services]
	hrd append start_nodes      [lindex $_res 0]
	hrd append routes           [lindex $_res 1]
	lappend runtime_archives {*}[lindex $_res 2]
	lappend rom_modules      {*}[lindex $_res 3]

	foreach service [array names provided_services] {
		log "runtime-declared provided '$service' will be ignored" }

	# bind services by target-specific implementation
	set _res [bind_required_services required_services]
	hrd append start_nodes      [lindex $_res 0]
	hrd append routes           [lindex $_res 1]
	lappend runtime_archives {*}[lindex $_res 2]
	lappend rom_modules      {*}[lindex $_res 3]

	# route remaining services to blackhole component
	set blackhole_config   [hrd create]
	set blackhole_provides [hrd create]

	foreach service [array names required_services] {
		if {[llength $required_services($service)] == 0} { continue }

		if {[lsearch -exact $blackhole_supported_services $service] > -1} {
			set cased_name [lindex $known_services [lsearch -exact -nocase $known_services $service]]

			hrd append blackhole_config   "+ $service"
			hrd append blackhole_provides "+ service $cased_name"

			foreach service_node $required_services($service) {
				node with-attribute $service_node "label" label {
					hrd append routes "+ service $cased_name | label_last: $label | + child black_hole"

					log "routing '$service label: \"$label\"' requirement to black-hole component"
				} default {
					hrd append routes "+ service $cased_name | + child black_hole"

					log "routing '$service' requirement to black-hole component"
				}
			}

		} else {
			foreach service_node $required_services($service) {
				log "runtime-declared '[hrd first [hrd format $service_node]]' requirement is not supported" }
		}
	}

	if {![hrd empty $blackhole_config]} {
		hrd append start_nodes "+ start black_hole | caps: 100 | ram: 2M" \
		                       "  + provides" [hrd indent 2 $blackhole_provides] \
		                       "  + config"   [hrd indent 2 $blackhole_config] \
		                       "  + route" \
		                       "    + service PD    | + parent" \
		                       "    + service CPU   | + parent" \
		                       "    + service LOG   | + parent" \
		                       "    + service ROM   | + parent" \
		                       "    + service Timer | + child timer"

		lappend rom_modules black_hole

		lappend runtime_archives "$run_as/src/black_hole"
	}

	set inline_config {}
	if {[hrd empty $config_route]} {
		set inline_config $config
	} else {
		set routes [hrd create $config_route $routes]
	}

	set parent_provides [hrd create "+ parent-provides" \
	                                "  + service ROM" \
	                                "  + service PD" \
	                                "  + service CPU" \
	                                "  + service LOG"]

	foreach s [parent_services] {
		hrd append parent_provides "  + service $s"
	}

	hrd append routes "+ service ROM | [rom_route]" \
	                  "+ service PD  | [pd_route]" \
	                  "+ service CPU | [cpu_route]" \
	                  "+ service LOG | [log_route]"

	if {![hrd empty $provides]} {
		set provides [hrd create "+ provides" [hrd indent 2 $provides]] }

	hrd append start_nodes "+ start $args(run_pkg) | caps: $caps | ram: $ram" \
	                       "  + binary $binary" \
	                       $provides \
	                       "  + route" [hrd indent 2 $routes] \
	                       [hrd indent 1 [hrd format $inline_config]]

	install_config [hrd create "+ config" \
	                           [hrd indent 1 $parent_provides] \
	                           [hrd indent 1 $start_nodes]]
	                      
	lappend runtime_archives {*}[base_archives]

	# remove duplicates from rom_modules but keep sorting of runtime_archives
	# intact because the order determines potential shadowing of files
	set rom_modules      [lsort -unique $rom_modules]
}
