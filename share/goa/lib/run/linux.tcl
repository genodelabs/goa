proc run_genode { } {
	global config::run_dir config::var_dir config::project_name config::depot_dir config::debug

	##
	# create helper file for gdb
	#
	if { $debug } {
		set gdb_file [file join $var_dir $project_name.gdb]

		set fd [open $gdb_file w]
		puts $fd "cd $var_dir/run"
		puts $fd "set non-stop on"
		puts $fd "set substitute-path /data/depot $depot_dir"
		puts $fd "set substitute-path /depot $depot_dir"
		close $fd
	}

	##
	# run the scenario
	#
	set orig_pwd [pwd]
	cd $run_dir
	eval spawn -noecho ./core
	cd $orig_pwd

	set timeout -1
	interact {
		\003 {
			send_user "Expect: 'interact' received 'strg+c' and was cancelled\n";
			return
		}
		-i $spawn_id
	}
}


proc parent_services { } {
	return [list RM TRACE]
}


proc base_archives { } {
	global config::run_as

	return [list "$run_as/src/base-linux" "$run_as/src/init"]
}


proc rom_route { } { return "+ parent" }
proc log_route { } { return "+ parent" }
proc pd_route  { } { return "+ parent" }
proc cpu_route { } { return "+ parent" }


proc bind_provided_services { &services } {
	# use upvar to access array
	upvar 1 ${&services} services

	# make sure to declare variables locally
	variable start_nodes routes archives modules

	set start_nodes [hrd create]
	set routes      [hrd create]
	set archives    { }
	set modules     { }

	# instantiate NIC driver in uplink mode if required by runtime
	if {[info exists services(uplink)]} {
		if { [llength ${services(uplink)}] > 1 } {
			log "Ignoring all but the first provided 'uplink' service." }

		node with-attribute [lindex ${services(uplink)} 0] "label" uplink_label {
			_instantiate_uplink_client $uplink_label start_nodes archives modules
		} default {
			_instantiate_uplink_client "" start_nodes archives modules
		}

		hrd append routes "+ service Uplink"

		unset services(uplink)
	}

	return [list $start_nodes $routes $archives $modules]
}


proc bind_required_services { &services } {
	# use upvar to access array
	upvar 1 ${&services} services

	# make sure to declare variables locally
	variable start_nodes routes archives modules

	set routes      [hrd create]
	set start_nodes [hrd create]
	set archives    { }
	set modules     { }

	# route parent services if required by runtime
	foreach service_name [parent_services] {
		set name_lc [string tolower $service_name]
		if {[info exists services($name_lc)]} {
			hrd append routes "+ service $service_name | + parent"
			unset services($name_lc)
		}
	}

	# always instantiate timer
	_instantiate_timer start_nodes archives modules

	# route timer if required by runtime
	if {[info exists services(timer)]} {
		hrd append routes "+ service Timer | + child timer"
		unset services(timer)
	}

	# route nitpicker services if required by runtime
	set use_nitpicker 0
	if {[info exists services(event)]} {
		set use_nitpicker 1
		hrd append routes "+ service Event | + child nitpicker"
		unset services(event)
	}

	if {[info exists services(capture)]} {
		set use_nitpicker 1
		hrd append routes "+ service Capture | + child nitpicker"
		unset services(capture)
	}

	if {[info exists services(gui)]} {
		set use_nitpicker 1
		hrd append routes "+ service Gui | label_suffix: backdrop"
		hrd append routes "  + child nitpicker | label: backdrop"
		hrd append routes "+ service Gui | + child nitpicker"
		unset services(gui)
	}

	if {$use_nitpicker} {
		_instantiate_nitpicker start_nodes archives modules }

	##
	# instantiate NIC router and driver if required by runtime
	if {[info exists services(nic)]} {
		set nic_services_unique [lsort -unique ${services(nic)}]
		if {[llength ${services(nic)}] != [llength $nic_services_unique]} {
			log "Ignoring duplicate 'nic' requirements" }

		set subnet_id 10
		array set networks { }
		foreach nic_node $nic_services_unique {

			node with-attribute $nic_node "label" value {
				set tap_name $value
			} default {
				set tap_name "tap0"
				set nic_node_short [hrd first [hrd format $nic_node]]
				log "Binding '$nic_node_short' to tap device '$tap_name'." \
				    "You can change the used tap device by adding a 'tap_name' attribute."
			}

			if {![info exists networks($tap_name)]} {
				set networks($tap_name) [_instantiate_network $tap_name $subnet_id \
				                                              start_nodes archives \
				                                              modules nic_node]

				incr subnet_id
				if {$subnet_id > 255} {
					exit_with_error "Too many 'nic' requirements" }
			}

			node with-attribute $nic_node "label" nic_label {
				hrd append routes "+ service Nic | label: $nic_label"
			} default {
				hrd append routes "+ service Nic"
			}
			hrd append routes "  + child $networks($tap_name)"
		}

		unset services(nic)
	}

	##
	# instantiate file systems
	if {[info exists services(file_system)]} {
		foreach fs_node $services(file_system) {
			variable label writeable name

			set label     ""
			set writeable "no"
			set name      "fs"

			node with-attribute $fs_node "label" value {
				set label $value
				set name "${label}_fs"

				node with-attribute $fs_node "writeable" value {
					set writeable $value
				} default { }

				hrd append routes "+ service File_system | label_prefix: $label ->"
				hrd append routes "  + child $name"

			} default {
				hrd append routes "+ service File_system"
				hrd append routes "  + child fs"
			}

			if {$label == "fonts"} {
				_instantiate_fonts_fs start_nodes archives modules
			} else {
				_instantiate_file_system $name $label $writeable start_nodes archives modules
			}
		}

		global config::run_dir config::var_dir
		# link all file systems to run_dir
		file link -symbolic "$run_dir/fs" "$var_dir/fs"

		unset services(file_system)
	}

	##
	# instantiate rtc driver if required by runtime
	if {[info exists services(rtc)]} {
		if {[llength ${services(rtc)}] > 1} {
			log "Ignoring all but the first required 'rtc' service" }

		hrd append routes "+ service Rtc | + child rtc"

		_instantiate_rtc start_nodes archives modules

		unset services(rtc)
	}

	##
	# add mesa gpu route if required by runtime
	if {[info exists services(rom)]} {
		set services(rom) [lmap rom_node ${services(rom)} {
			node with-attribute $rom_node "label" label {
				if {$label == "mesa_gpu.lib.so"} {
					hrd append routes "+ service ROM | label: mesa_gpu.lib.so" 
					hrd append routes "  + parent | label: mesa_gpu-softpipe.lib.so"

					lappend modules mesa_gpu-softpipe.lib.so

					return -code continue
				}
			} default { }

			set rom_node
		}]
	}

	##
	# instantiate report_rom if clipboard Report or ROM required by runtime
	set clipboard_rom_node ""
	set clipboard_report_node ""
	if {[info exists services(rom)]} {
		set services(rom) [lmap rom_node ${services(rom)} {
			node with-attribute $rom_node "label" label {
				if {$label == "clipboard"} {
					set clipboard_rom_node $rom_node
					return -code continue
				}
			} default { }

			set rom_node
		}]
	}
	if {[info exists services(report)]} {
		set services(report) [lmap report_node ${services(report)} {
			node with-attribute $report_node "label" label {
				if {$label == "clipboard"} {
					set clipboard_report_node $report_node
					return -code continue
				}
			} default { }

			set report_node
		}]
	}

	if {$clipboard_rom_node != ""} {
		hrd append routes "+ service ROM | label: clipboard | + child clipboard" }

	if {$clipboard_report_node != ""} {
		hrd append routes "+ service Report | label: clipboard | + child clipboard" }

	if {$clipboard_rom_node != "" || $clipboard_report_node != ""} {
		_instantiate_clipboard start_nodes archives modules }

	##
	# instantiate external ROMs if required by runtime
	if {[info exists services(rom)]} {
		set provided_external_rom 0
		set services(rom) [lmap rom_node $services(rom) {
			node with-attribute $rom_node "label" label {
				hrd append routes "+ service ROM | label: $label | + child rom"
				incr provided_external_rom
				return -code continue
			} default { }
			set rom_node
		}]

		# only start one instance of the components
		if {$provided_external_rom > 0} {
			_instantiate_rom_provider start_nodes archives modules

			# link the rom directory
			global config::run_dir config::var_dir
			file link -symbolic "$run_dir/rom" "$var_dir/rom"
		}
	}

	return [list $start_nodes $routes $archives $modules ]
}

proc _instantiate_timer { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	hrd append start_nodes "+ start timer | caps: 100 | ram: 1M" \
	                       "  + provides | + service Timer" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent"

	lappend modules timer
}


proc _instantiate_nitpicker { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::run_as

	hrd append start_nodes "+ start drivers | caps: 1000" \
	                       "                | ram: 36M" \
	                       "                | managing_system: yes" \
	                       "  + binary init" \
	                       "  + route" \
	                       "     + service ROM | label: config" \
	                       "       + parent | label: drivers.config" \
	                       "     + service Timer   | + child timer" \
	                       "     + service Capture | + child nitpicker" \
	                       "     + service Event   | + child nitpicker" \
	                       "     + any-service | + parent" \
	                       "+ start report_rom | caps: 100 | ram: 1M" \
	                       "  + provides" \
	                       "    + service Report" \
	                       "    + service ROM" \
	                       "  + config | verbose: no" \
	                       "    + policy | label_prefix: focus_rom" \
	                       "             | report: nitpicker -> hover" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent" \
	                       "+ start focus_rom | caps: 100 | ram: 1M" \
	                       "  + binary rom_filter" \
	                       "  + provides | + service ROM" \
	                       "  + config" \
	                       "    + input hovered_label | rom: hover | node: hover" \
	                       "      + attribute label" \
	                       "    + output | node: focus" \
	                       "      + attribute label | input: hovered_label" \
	                       "  + route" \
	                       "    + service ROM | label: hover | + child report_rom" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent" \
	                       "+ start nitpicker | caps: 100 | ram: 4M" \
	                       "  + provides" \
	                       "    + service Gui" \
	                       "    + service Capture" \
	                       "    + service Event" \
	                       "  + config | focus: rom" \
	                       "    + capture" \
	                       "    + event" \
	                       "    + report | hover: yes" \
	                       "    + background | color: #115588" \
	                       "    + domain pointer    | layer: 1" \
	                       "                        | content: client" \
	                       "                        | label: no" \
	                       "                        | origin: pointer" \
	                       "    + domain default    | layer: 2" \
	                       "                        | content: client" \
	                       "                        | label: no" \
	                       "                        | hover: always" \
	                       "    + domain background | layer: 3" \
	                       "                        | content: client" \
	                       "                        | label: no" \
	                       "                        | hover: always" \
	                       "                        | focus: transient" \
	                       "    + policy | label_prefix: pointer" \
	                       "             | domain: pointer" \
	                       "    + policy | label_suffix: backdrop" \
	                       "             | domain: background" \
	                       "    + default-policy | domain: default" \
	                       "  + route" \
	                       "    + service ROM | label: focus | + child focus_rom" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent" \
	                       "    + service Timer  | + child timer" \
	                       "    + service Report | + child report_rom" \
	                       "+ start pointer | caps: 100 | ram: 1M" \
	                       "  + config" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent" \
	                       "    + service Gui | + child nitpicker"
	                   
	lappend modules nitpicker \
	                pointer \
	                fb_sdl \
	                event_filter \
	                drivers.config \
	                event_filter.config \
	                en_us.chargen \
	                special.chargen \
	                report_rom \
	                rom_filter

	lappend archives "$run_as/src/nitpicker"
	lappend archives "$run_as/src/report_rom"
	lappend archives "$run_as/src/rom_filter"
	lappend archives "$run_as/pkg/drivers_interactive-linux"
}


proc _instantiate_network { tap_name subnet_id &start_nodes &archives &modules &nic_node } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules
	upvar 1 ${&nic_node} nic_node

	global config::run_as

	set driver_name nic_$tap_name
	set router_name nic_router_$tap_name

	set forward_rules [hrd create]

	node for-each-node $nic_node "tcp-forward" rule {
		hrd append forward_rules [hrd format $rule] }

	node for-each-node $nic_node "udp-forward" rule {
		hrd append forward_rules [hrd format $rule] }

	set extra_domains [hrd create]
	node for-each-node $nic_node "domain" domain {
		hrd append extra_domains [hrd format $domain] }

	set extra_policies [hrd create]
	node for-each-node $nic_node "policy" policy {
		hrd append extra_policies [hrd format $policy] }

	hrd append start_nodes "+ start $driver_name | caps: 100 | ld: no | ram: 4M" \
	                       "  + binary linux_nic" \
	                       "  + provides | + service Nic" \
	                       "  + config | tap: $tap_name" \
	                       "  + route" \
	                       "    + service Uplink | + child $router_name" \
	                       "    + any-service | + parent" \
	                       "+ start $router_name | caps: 200 | ram: 10M" \
	                       "  + binary nic_router" \
	                       "  + provides" \
	                       "    + service Uplink" \
	                       "    + service Nic" \
	                       "  + config | verbose_domain_state: yes" \
	                       "    + default-policy | domain: default" \
	                       "    + policy | label_prefix: $driver_name -> | domain: uplink" \
	                       [hrd indent 2 $extra_policies] \
	                       "    + domain uplink" \
	                       "      + nat | domain: default" \
	                       "            | tcp-ports: 1000" \
	                       "            | udp-ports: 1000" \
	                       "            | icmp-ids:  1000" \
	                       [hrd indent 3 $forward_rules] \
	                       "    + domain default | interface: 10.0.$subnet_id.1/24" \
	                       "      + dhcp-server | ip_first: 10.0.$subnet_id.2" \
	                       "                    | ip_last:  10.0.$subnet_id.253" \
	                       "                    | dns_config_from: uplink" \
	                       "      + tcp | dst: 0.0.0.0/0" \
	                       "        + permit-any | domain: uplink" \
	                       "      + udp | dst: 0.0.0.0/0" \
	                       "        + permit-any | domain: uplink" \
	                       "      + icmp | dst: 0.0.0.0/0 | domain: uplink" \
	                       [hrd indent 2 $extra_domains] \
	                       "  + route" \
	                       "    + service Timer | + child name: timer" \
	                       "    + any-service | + parent"

	lappend modules linux_nic nic_router

	lappend archives "$run_as/src/linux_nic"
	lappend archives "$run_as/src/nic_router"

	return $router_name
}


proc _instantiate_uplink_client { uplink_label &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::project_name config::run_as

	hrd append start_nodes "+ start nic | caps: 100 | ld: no | ram: 4M" \
	                       "  + binary linux_nic" \
	                       "  + provides | + service Uplink" \
	                       
	if {$uplink_label != ""} {
		hrd append start_nodes "  + config | tap: $uplink_label" }

	hrd append start_nodes "  + route" \
	                       "    + service Uplink | + child $project_name" \
	                       "    + any-service | + parent"

	lappend modules linux_nic

	lappend archives "$run_as/src/linux_nic"
}


proc _instantiate_fonts_fs { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::run_as

	hrd append start_nodes "+ start fonts_fs | caps: 100 | ram: 2M" \
	                       "  + binary vfs" \
	                       "  + provides | + service File_system" \
	                       "  + route" \
	                       "    + service ROM | label: config" \
	                       "      + parent | label: fonts_fs.config" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent"
	                       
	lappend modules vfs fonts_fs.config

	lappend archives $run_as/pkg/fonts_fs
}


proc _instantiate_file_system { name label writeable &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::var_dir config::run_as

	# make sure label is not empty
	if {$label == ""} { set label "_" }

	hrd append start_nodes "+ start $name | caps: 100 | ld: no | ram: 1M" \
	                       "  + binary lx_fs" \
	                       "  + provides | + service File_system" \
	                       "  + config" \
	                       "    + default-policy | root: /fs/$label" \
	                       "                     | writeable: $writeable" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent"

	# create folder in var_dir
	set fs_dir "$var_dir/fs/$label"
	if {![file isdirectory $fs_dir]} {
		log "creating file-system directory $fs_dir"
		file mkdir $fs_dir
	}

	lappend modules lx_fs

	lappend archives "$run_as/src/lx_fs"
}


proc _instantiate_rom_provider { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::run_as config::var_dir

	hrd append start_nodes "+ start rom_fs | caps: 100 | ld: no | ram: 1M" \
	                       "  + binary lx_fs" \
	                       "  + provides | + service File_system" \
	                       "  + config" \
	                       "    + default-policy | root: /rom" \
	                       "                     | writeable: no" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent" \
	                       "+ start rom | caps: 100 | ram: 1M" \
	                       "  + binary fs_rom" \
	                       "  + provides | + service ROM" \
	                       "  + config" \
	                       "  + route" \
	                       "    + service File_system | + child rom_fs" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent"

	# create folder in var_dir
	set fs_dir "$var_dir/rom"
	if {![file isdirectory $fs_dir]} {
		log "creating file-system directory $fs_dir"
		file mkdir $fs_dir
	}

	lappend modules fs_rom lx_fs

	lappend archives $run_as/src/fs_rom
	lappend archives $run_as/src/lx_fs
}


proc _instantiate_rtc { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::run_as

	hrd append start_nodes "+ start rtc | caps: 100 | ld: no | ram: 1M" \
	                       "  + binary linux_rtc" \
	                       "  + provides | + service Rtc" \
	                       "  + route | + any-service | + parent"

	lappend modules linux_rtc

	lappend archives "$run_as/src/linux_rtc"
}


proc _instantiate_clipboard { &start_nodes &archives &modules } {
	upvar 1 ${&start_nodes} start_nodes
	upvar 1 ${&archives} archives
	upvar 1 ${&modules} modules

	global config::project_name config::run_as

	hrd append start_nodes "+ start clipboard | caps: 100 | ram: 2M" \
	                       "  + binary report_rom" \
	                       "  + provides" \
	                       "    + service Report" \
	                       "    + service ROM" \
	                       "  + config | verbose: yes" \
	                       "    + policy | label_suffix: clipboard" \
	                       "             | report: $project_name -> clipboard" \
	                       "  + route" \
	                       "    + service PD  | + parent" \
	                       "    + service CPU | + parent" \
	                       "    + service LOG | + parent" \
	                       "    + service ROM | + parent"
	lappend modules report_rom

	lappend archives "$run_as/src/report_rom"
}
