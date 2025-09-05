proc run_genode { } {
	global tool_dir
	global config::run_dir config::var_dir config::target config::target_opt
	global config::project_name config::depot_dir config::debug

	if {![info exists target_opt($target-server)]} {
		exit_with_error "missing target option '$target-server'\n" \
		                "\n define 'set target_opt($target-server) <url>' in your" \
		                "\n goarc file, or specify '--target-opt-$target-server <url>'" \
		                "\n as command-line argument\n"
	}

	set port_http 80
	if {[info exists target_opt($target-port-http)]} {
		set port_http $target_opt($target-port-http) }

	set port_telnet 23
	if {[info exists target_opt($target-port-telnet)]} {
		set port_telnet $target_opt($target-port-telnet) }

	set port_gdb 9999
	if {[info exists target_opt($target-port-gdb)]} {
		set port_gdb $target_opt($target-port-gdb) }

	set host        $target_opt($target-server)

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
		puts $fd "target extended-remote $host:$port_gdb"
		close $fd
	}

	# create lambda to make config-deletion command re-usable
	set clear_config {{cmd} {
		diag "deleting config from server via: $cmd config DELETE=1"
		if {[catch { exec {*}$cmd config DELETE=1 >@stdout} msg]} {
			exit_with_error $msg }
	}}

	set     cmd "make"
	lappend cmd "-f" [file join $tool_dir lib sync_http.mk]
	lappend cmd "TMP_DIR=[file join $var_dir targets $target]"
	lappend cmd "SRC_DIR=$run_dir"
	lappend cmd "SERVER=http://$host:$port_http"

	# make sure the remote config is empty
	apply $clear_config $cmd

	# sync all files expect config
	set modules [glob -type f -directory $run_dir -tails *]
	set modules [lsearch -inline -all -not -exact $modules config]
	diag "uploading modules to server via: $cmd $modules"
	if {[catch { exec {*}$cmd {*}$modules >@ stdout} msg]} {
		exit_with_error $msg }
	
	# sync config and thereby start the scenario
	diag "uploading config to server via: $cmd config"
	if {[catch { exec {*}$cmd config >@stdout} msg]} {
		exit_with_error $msg }

	# spawn optional command if target-opt-sculpt-cmd is set
	if {[info exists target_opt($target-cmd)]} {
		set    opt_cmd "SERVER=$host;"
		append opt_cmd {*}$target_opt($target-cmd)

		# ask user for confirmation before spawning optional command
		if {[user_confirmation "Do you want to run '$opt_cmd'?" 1]} {
			spawn sh -c "$opt_cmd"
			set cmd_spawn_id $spawn_id
		}
	}

	eval spawn -noecho telnet $host $port_telnet

	set timeout -1
	interact {
		\003 {
			send_user "Expect: 'interact' received 'strg+c' and was cancelled\n";
			# delete config on remote target
			apply $clear_config $cmd
			return
		}
		-i $spawn_id
	}

	# terminate optional command
	if {[info exists cmd_spawn_id]} {
		close -i $cmd_spawn_id
		wait -i $cmd_spawn_id
	}
}


proc parent_services { } {
	return [list TRACE RM VM Timer Rtc Gui Nic Event Capture Platform \
	             Audio_out Audio_in Play Record Usb Gpu Report File_system] }


proc base_archives { } {
	global config::run_as config::target config::target_opt

	if {[info exists target_opt($target-kernel)]} {
		set kernel $target_opt($target-kernel)
		return [list "$run_as/src/base-$kernel"]
	}

	return {}
}


proc rom_route { } { return "+ parent" }
proc log_route { } { return "+ parent" }


proc pd_route  { } {
	global config::debug
	if { $debug } { return "+ local" }

	return "+ parent"
}


proc cpu_route { } {
	global config::debug
	if { $debug } { return "+ local" }

	return "+ parent"
}


proc bind_provided_services { &services } {
	# use upvar to access array
	upvar 1 ${&services} services

	# instantiate NIC driver in uplink mode if required by runtime
	foreach name [array names services] {
		log "Ignoring provided '$name' service." }

	return [list { } { } { } { }]
}


proc bind_required_services { &services } {
	global args
	global config::debug config::target config::target_opt

	# use upvar to access array
	upvar 1 ${&services} services

	# make sure to declare variables locally
	variable start_nodes routes archives modules

	set routes      [hrd create]
	set start_nodes [hrd create]
	set archives    { }
	set modules     { }

	if { $debug } {
		hrd append start_nodes "+ monitor | max_response: 2K" \
		                       "  + policy | label_prefix: $args(run_pkg)" \
		                       "           | wait: no" \
		                       "           | stop: no" \
		                       "           | wx: yes"
	}

	if {[info exists target_opt($target-kernel)]} {
		hrd append routes "+ service ROM | label_last: ld.lib.so" \
		                  "  + parent | label: ld.lib.so.local" \
		                  "+ service ROM | unscoped_label: ld.lib.so" \
		                  "  + parent | label: ld.lib.so.local"
	}

	##
	# instantiate fonts_fs
	if {[info exists services(file_system)]} {
		set unknown_fs_label 0
		foreach fs_node $services(file_system) {
			variable label
			node with-attribute $fs_node "label" label {
				if {$label == "fonts"} {
					hrd append routes "+ service File_system | label_prefix: fonts ->" \
					                  "  + child fonts_fs"
				} else {
					set unknown_fs_label 1
				}
			} default {
				set unknown_fs_label 1
			}
		}

		# unsetting prevents that a generic parent route is added below
		if {!$unknown_fs_label} {
			unset services(file_system)
		}
	}

	##
	# route known ROMs by label
	if {[info exists services(rom)]} {
		set unknown_rom_label 0
		set known_roms [list clipboard platform_info capslock]
		foreach rom_node $services(rom) {
			variable label
			node with-attribute $rom_node "label" label {
				if {[lsearch -exact $known_roms $label] > -1} {
					hrd append routes "+ service ROM | label: $label" \
					                  "  + parent | label: $label"
				} else {
					set unknown_rom_label 1
				}
				
			} default {
				set unknown_rom_label 1
			}
		}

		if {$unknown_rom_label} {
			hrd append routes "+ service ROM | + parent" }

		unset services(rom)
	}


	##
	# route known Reports by label
	if {[info exists services(report)]} {
		set unknown_report_label 0
		set known_reports [list clipboard shape]
		foreach report_node $services(report) {
			variable label
			node with-attribute $report_node "label" label {
				if {[lsearch -exact $known_reports $label] > -1} {
					hrd append routes "+ service Report | label: $label" \
					                  "  + parent | label: $label"
					_instantiate_fonts_fs start_nodes archives modules
				} else {
					set unknown_report_label 1
				}
				
			} default {
				set unknown_report_label 1
			}
		}

		# unsetting prevents that a generic parent route is added below
		if {!$unknown_report_label} {
			unset services(report)
		}
	}


	# route remaining parent services if required by runtime
	foreach name [parent_services] {
		set name_lc [string tolower $name]
		if {[info exists services($name_lc)]} {
			hrd append routes "+ service $name | + parent"
			unset services($name_lc)
		}
	}

	return [list $start_nodes $routes $archives $modules ]
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
