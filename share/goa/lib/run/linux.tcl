
proc generate_runtime_config { } {
	global runtime_archives runtime_file project_name rom_modules run_dir var_dir config_valid run_as

	set ram    [try_query_attr_from_runtime ram]
	set caps   [try_query_attr_from_runtime caps]
	set binary [try_query_attr_from_runtime binary]

	set config_valid 0

	set config ""
	catch {
		set config [query_node /runtime/config $runtime_file]
		set config [desanitize_xml_characters $config]
	}

	set config_route ""
	catch {
		set rom_name [query_attr /runtime config $runtime_file]
		append config_route "\n\t\t\t\t\t" \
		                    "<service name=\"ROM\" label=\"config\"> " \
		                    "<parent label=\"$rom_name\"/> " \
		                    "</service>"

		if {$config != ""} {
			exit_with_error "runtime config is ambiguous,"
			                "specified as 'config' attribute as well as '<config>' node" }
	}

	if {$config != "" || $config_route != ""} {
		set config_valid 1 }

	set gui_config_nodes ""
	set gui_route        ""
	set capture_route ""
	set event_route ""
	catch {
		set capture_node ""
		set event_node ""
		catch {
			set capture_node [query_node /runtime/requires/capture $runtime_file]

			append capture_route "\n\t\t\t\t\t" \
			                     "<service name=\"Capture\"> " \
			                     "<child name=\"nitpicker\"/> " \
			                     "</service>"
		}
		catch {
			set event_node   [query_node /runtime/requires/event $runtime_file]

			append event_route "\n\t\t\t\t\t" \
			                     "<service name=\"Event\"> " \
			                     "<child name=\"nitpicker\"/> " \
			                     "</service>"
		}
		if {$capture_node == "" && $event_node == ""} {
			set gui_node [query_node /runtime/requires/gui $runtime_file] }

		append gui_config_nodes {
			<start name="drivers" caps="1000">
				<resource name="RAM" quantum="32M" constrain_phys="yes"/>
				<binary name="init"/>
				<route>
					<service name="ROM" label="config"> <parent label="drivers.config"/> </service>
					<service name="Timer">   <child name="timer"/> </service>
					<service name="Capture"> <child name="nitpicker"/> </service>
					<service name="Event">   <child name="nitpicker"/> </service>
					<any-service> <parent/> </any-service>
				</route>
			</start>

			<start name="report_rom" caps="100">
				<resource name="RAM" quantum="1M"/>
				<provides> <service name="Report"/> <service name="ROM"/> </provides>
				<config verbose="no">
					<policy label_prefix="focus_rom" report="nitpicker -> hover"/>
				</config>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>

			<start name="focus_rom" caps="100">
				<binary name="rom_filter"/>
				<resource name="RAM" quantum="1M"/>
				<provides> <service name="ROM"/> </provides>
				<config>
					<input name="hovered_label" rom="hover" node="hover">
						<attribute name="label" />
					</input>
					<output node="focus">
						<attribute name="label" input="hovered_label"/>
					</output>
				</config>
				<route>
					<service name="ROM" label="hover"> <child name="report_rom"/> </service>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>

			<start name="nitpicker" caps="100">
				<resource name="RAM" quantum="4M"/>
				<provides>
					<service name="Gui"/> <service name="Capture"/> <service name="Event"/>
				</provides>
				<route>
					<service name="ROM" label="focus"> <child name="focus_rom"/> </service>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
					<service name="Timer">  <child name="timer"/> </service>
					<service name="Report"> <child name="report_rom"/> </service>
				</route>
				<config focus="rom">
					<capture/> <event/>
					<report hover="yes"/>
					<domain name="pointer" layer="1" content="client" label="no" origin="pointer" />
					<domain name="default" layer="2" content="client" label="no" hover="always"/>

					<policy label_prefix="pointer" domain="pointer"/>
					<default-policy domain="default"/>
				</config>
			</start>

			<start name="pointer" caps="100">
				<resource name="RAM" quantum="1M"/>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
					<service name="Gui"> <child name="nitpicker"/> </service>
				</route>
				<config/>
			</start>
		}

		append gui_route "\n\t\t\t\t\t" \
		                 "<service name=\"Gui\"> " \
		                 "<child name=\"nitpicker\"/> " \
		                 "</service>"
	}

	set nic_config_nodes ""
	set nic_route        ""
	catch {
		set nic_node [query_node /runtime/requires/nic $runtime_file]
		set nic_label [query_node string(/runtime/requires/nic/@label) $runtime_file]

		append nic_config_nodes {
			<start name="nic_drv" caps="100" ld="no">
				<binary name="linux_nic_drv"/>
				<resource name="RAM" quantum="4M"/>
				<provides> <service name="Nic"/> </provides>}
		if {$nic_label != ""} {
			append nic_config_nodes {
				<config tap="} $nic_label {"/>}
		}
		append nic_config_nodes {
				<route>
					<service name="Uplink"> <child name="nic_router"/> </service>
					<any-service> <parent/> </any-service>
				</route>
			</start>

			<start name="nic_router" caps="200">
				<resource name="RAM" quantum="10M"/>
				<provides>
					<service name="Uplink"/>
					<service name="Nic"/>
				</provides>
				<config verbose_domain_state="yes">
					<default-policy domain="default"/>
					<policy label="nic_drv -> " domain="uplink"/>
					<domain name="uplink">
						<nat domain="default" tcp-ports="1000" udp-ports="1000" icmp-ids="1000"/>
					</domain>
					<domain name="default" interface="10.0.1.1/24">
						<dhcp-server ip_first="10.0.1.2" ip_last="10.0.1.253"/>
						<tcp dst="0.0.0.0/0">
							<permit-any domain="uplink"/>
						</tcp>
						<udp dst="0.0.0.0/0">
							<permit-any domain="uplink"/>
						</udp>
						<icmp dst="0.0.0.0/0" domain="uplink"/>
					</domain>
				</config>
				<route>
					<service name="Timer"> <child name="timer"/> </service>
					<any-service> <parent/> </any-service>
				</route>
			</start>
		}

		append nic_route "\n\t\t\t\t\t" \
			{<service name="Nic"> <child name="nic_router"/> </service>}
	}

	set uplink_config_nodes ""
	set uplink_provides     ""
	catch {
		set uplink_node [query_node /runtime/requires/uplink $runtime_file]
		set uplink_label [query_node string(/runtime/requires/uplink/@label) $runtime_file]

		append uplink_config_nodes "\n" {
			<start name="nic_drv" caps="100" ld="no">
				<binary name="linux_nic_drv"/>
				<resource name="RAM" quantum="4M"/>
				<provides> <service name="Uplink"/> </provides>}
		if {$uplink_label != ""} {
			append uplink_config_nodes {
				<config tap="} $uplink_label {"/>}
		}
		append uplink_config_nodes {
				<route>
					<service name="Uplink"> <child name="} $project_name {"/> </service>
					<any-service> <parent/> </any-service>
				</route>
			</start>
		}
		append uplink_provides "\n\t\t\t\t\t" \
			{<service name="Uplink"/>}
	}

	set fs_config_nodes ""
	set fs_routes       ""
	foreach {label writeable} [required_file_systems $runtime_file] {
		set label_fs "${label}_fs"

		append fs_config_nodes {
			<start name="} "$label_fs" {" caps="100" ld="no">
				<binary name="lx_fs"/>
				<resource name="RAM" quantum="1M"/>
				<provides> <service name="File_system"/> </provides>
				<config>
					<default-policy root="/fs/} $label {" writeable="} $writeable {" />
				</config>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>
		}

		append fs_routes "\n\t\t\t\t\t" \
			"<service name=\"File_system\" label=\"$label\"> " \
			"<child name=\"$label_fs\"/> " \
			"</service>"

		set fs_dir "$var_dir/fs/$label"
		if {![file isdirectory $fs_dir]} {
			log "creating file-system directory $fs_dir"
			file mkdir $fs_dir
		}
	}

	set clipboard_config_nodes ""
	set clipboard_route ""
	catch {
		set node [query_node /runtime/requires/rom\[@label="clipboard"\] $runtime_file]
		append clipboard_route {
					<service name="ROM" label="clipboard">} \
					{    <child name="clipboard"/> </service>}
	}
	catch {
		set node [query_node /runtime/requires/report\[@label="clipboard"\] $runtime_file]
		append clipboard_route {
					<service name="Report" label="clipboard">} \
					{ <child name="clipboard"/> </service>}
	}

	if {$clipboard_route != ""} {
		append clipboard_config_nodes {
			<start name="clipboard" caps="100">
				<binary name="report_rom"/>
				<resource name="RAM" quantum="2M"/>
				<provides>
					<service name="Report"/>
					<service name="ROM"/>
				</provides>
				<config verbose="yes">
					<policy label_suffix="clipboard" report="} $project_name { -> clipboard"/>
				</config>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>
		}
	}


	set blackhole_config_nodes ""
	set blackhole_route ""
	set blackhole_config ""
	set blackhole_services ""
	catch {
		set node [query_node /runtime/requires/report\[@label!="clipboard"\] $runtime_file]
		append blackhole_config {
					<report/>}
		append blackhole_services {
					<service name="Report"/>}

		# iterate all report nodes and their labels (except "clipboard")
		foreach {label} [lsearch -inline -all -not -exact \
			              [required_report_labels $runtime_file] "clipboard"] {
			append blackhole_route {
					<service name="Report" label_suffix=" -> } $label {">}\
					{ <child name="black_hole"/> </service>}
		}
	}
	catch {
		set node [query_node /runtime/requires/audio_in $runtime_file]
		puts $node
		append blackhole_config {
					<audio_in/>}
		append blackhole_services {
					<service name="Audio_in"/>}
		append blackhole_route {
					<service name="Audio_in">  <child name="black_hole"/> </service>}
	}
	catch {
		set node [query_node /runtime/requires/audio_out $runtime_file]
		append blackhole_config {
					<audio_out/>}
		append blackhole_services {
					<service name="Audio_out"/>}
		append blackhole_route {
					<service name="Audio_out"> <child name="black_hole"/> </service>}
	}

	if {$blackhole_config != ""} {
		append blackhole_config_nodes {
			<start name="black_hole" caps="100">
				<resource name="RAM" quantum="2M"/>
				<provides> } $blackhole_services {
				</provides>
				<config> } $blackhole_config {
				</config>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>
		}
	}

	set rtc_config_nodes ""
	set rtc_route        ""
	catch {
		set rtc_node [query_node /runtime/requires/rtc $runtime_file]

		append rtc_config_nodes {
			<start name="rtc_drv" caps="100" ld="no">
				<binary name="linux_rtc_drv"/>
				<resource name="RAM" quantum="1M"/>
				<provides> <service name="Rtc"/> </provides>
				<route> <any-service> <parent/> </any-service> </route>
			</start>
		}

		append rtc_route "\n\t\t\t\t\t" \
		                     "<service name=\"Rtc\"> " \
		                     "<child name=\"rtc_drv\"/> " \
		                     "</service>"
	}

	set mesa_route ""
	catch {
		set gpu_node [query_node /runtime/requires/gpu $runtime_file]

		append mesa_route "\n\t\t\t\t\t" \
			"<service name=\"ROM\" label=\"mesa_gpu_drv.lib.so\"> " \
			"<parent label=\"mesa_gpu-softpipe.lib.so\"/> " \
			"</service>"
	}

	install_config {
		<config>
			<parent-provides>
				<service name="ROM"/>
				<service name="PD"/>
				<service name="RM"/>
				<service name="CPU"/>
				<service name="LOG"/>
				<service name="TRACE"/>
			</parent-provides>

			<start name="timer" caps="100">
				<resource name="RAM" quantum="1M"/>
				<provides><service name="Timer"/></provides>
				<route>
					<service name="PD">  <parent/> </service>
					<service name="CPU"> <parent/> </service>
					<service name="LOG"> <parent/> </service>
					<service name="ROM"> <parent/> </service>
				</route>
			</start>

			} $gui_config_nodes \
			  $nic_config_nodes \
			  $uplink_config_nodes \
			  $fs_config_nodes \
			  $clipboard_config_nodes \
			  $blackhole_config_nodes \
			  $rtc_config_nodes {

			<start name="} $project_name {" caps="} $caps {">
				<resource name="RAM" quantum="} $ram {"/>
				<binary name="} $binary {"/>
				<provides>} $uplink_provides {</provides>
				<route>} $config_route $gui_route \
				         $capture_route $event_route \
				         $nic_route $fs_routes $rtc_route \
				         $mesa_route $clipboard_route $blackhole_route {
					<service name="ROM">   <parent/> </service>
					<service name="PD">    <parent/> </service>
					<service name="RM">    <parent/> </service>
					<service name="CPU">   <parent/> </service>
					<service name="LOG">   <parent/> </service>
					<service name="TRACE"> <parent/> </service>
					<service name="Timer"> <child name="timer"/> </service>
				</route>
				} $config {
			</start>
		</config>
	}

	set rom_modules [content_rom_modules $runtime_file]
	lappend rom_modules core ld.lib.so timer init

	if {$gui_config_nodes != ""} {
		lappend rom_modules nitpicker \
		                    pointer \
		                    fb_sdl \
		                    event_filter \
		                    drivers.config \
		                    event_filter.config \
		                    en_us.chargen \
		                    special.chargen \
		                    report_rom \
		                    rom_filter

		lappend runtime_archives "$run_as/src/nitpicker"
		lappend runtime_archives "$run_as/src/report_rom"
		lappend runtime_archives "$run_as/src/rom_filter"
		lappend runtime_archives "$run_as/pkg/drivers_interactive-linux"

	}

	if {$nic_config_nodes != "" || $uplink_config_nodes != ""} {
		lappend rom_modules linux_nic_drv

		lappend runtime_archives "$run_as/src/linux_nic_drv"
	}

	if {$nic_config_nodes != ""} {
		lappend rom_modules nic_router

		lappend runtime_archives "$run_as/src/nic_router"
	}

	if {$fs_config_nodes != ""} {
		lappend rom_modules lx_fs

		lappend runtime_archives "$run_as/src/lx_fs"

		file link -symbolic "$run_dir/fs" "$var_dir/fs"
	}

	if {$clipboard_config_nodes != ""} {
		lappend rom_modules report_rom

		lappend runtime_archives "$run_as/src/report_rom"
	}

	if {$blackhole_config_nodes != ""} {
		lappend rom_modules black_hole

		lappend runtime_archives "$run_as/src/black_hole"
	}

	if {$rtc_config_nodes != ""} {
		lappend rom_modules linux_rtc_drv

		lappend runtime_archives "$run_as/src/linux_rtc_drv"
	}

	lappend runtime_archives "$run_as/src/init"
	lappend runtime_archives "$run_as/src/base-linux"

	if {$mesa_route != ""} {
		lappend rom_modules mesa_gpu-softpipe.lib.so
	}
}


proc run_genode { } {
	global run_dir

	set orig_pwd [pwd]
	cd $run_dir
	eval spawn -noecho ./core
	cd $orig_pwd

	set timeout -1
	interact {
		\003 {
			send_user "Expect: 'interact' received 'strg+c' and was cancelled\n";
			exit
		}
		-i $spawn_id
	}
}
