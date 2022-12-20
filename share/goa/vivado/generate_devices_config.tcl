#!/usr/bin/tclsh

package require tdom

set output "devices_manager.config"
if { $::argc > 0 } {
	for {set i 0} {$i < $::argc} {incr i} {
		set option [string trim [lindex $::argv $i]]
		switch -regexp -- $option {
			"--output"     { incr i; set output   [lindex $::argv $i] }
			"--template"   { incr i; set template [lindex $::argv $i] }
			"--xsa"        { incr i; set xsa      [lindex $::argv $i] }
		default {
			if { [regexp {^-} $option] } {
				puts "ERROR: Unknown option '$option' specified.\n"
				return 1
			}
		}}
	}
}


set bit_name     [file tail [file rootname $xsa].bit]
set sysdef_doc   [dom parse [exec unzip -p $xsa sysdef.xml]]
set default_bd   [[$sysdef_doc selectNodes //File\[@BD_TYPE="DEFAULT_BD"\]] @Name]
set xsa_doc      [dom parse [exec unzip -p $xsa $default_bd]]
set template_doc [dom parse [exec cat $template]]

set out_xml "
<config>
	<bitstream name=\"$bit_name\">
		<devices/>
	</bitstream>
</config>
"

set out_doc [dom parse $out_xml]
set out_node [$out_doc selectNodes /config/bitstream/devices]

foreach device [$template_doc selectNodes //device] {
	# find module by type/name in xsa
	foreach module [$xsa_doc selectNodes //MODULE] {
		set modtype  [$module @MODTYPE]
		set instance [$module @INSTANCE]
		if {[$device hasAttribute type] && $modtype  != [$device @type]} { continue }
		if {[$device hasAttribute name] && $instance != [$device @name]} { continue }

		set node [$out_doc createElement device]
		$node setAttribute type $modtype
		$node setAttribute name $instance

		# add <io_mem> for each corresponding memrange
		set memranges [$xsa_doc selectNodes //MEMRANGE\[@MEMTYPE="REGISTER"\]\[@INSTANCE="$instance"\]]
		foreach memrange $memranges {
			set io_mem_base [$memrange @BASEVALUE]
			set io_mem_high [$memrange @HIGHVALUE]
			$node appendXML "<io_mem address=\"$io_mem_base\" size=\"[format 0x%x [expr $io_mem_high - $io_mem_base + 1]]\"/>"
		}

		# copy irq nodes
		foreach irq [$device selectNodes .//irq] {
			$node appendXML [$irq asXML]
		}

		# copy reserved_memory nodes
		foreach reserved_mem [$device selectNodes .//reserved_memory] {
			$node appendXML [$reserved_mem asXML]
		}

		# copy reset-domain nodes
		foreach reset [$device selectNodes .//reset-domain] {
			$node appendXML [$reset asXML]
		}

		# copy power-domain nodes
		foreach power [$device selectNodes .//power-domain] {
			$node appendXML [$power asXML]
		}

		# find clocks
		set clocklist [list]
		foreach clk [$module selectNodes .//PORT\[@CLKFREQUENCY\]] {
			set connection [$clk selectNodes .//CONNECTION\[@PORT\]]
			if {[regexp "FCLK_CLK(\[0-9\])" [$connection @PORT] clkname clknum]} {
				if {$clkname in $clocklist} { continue }
				$node appendXML "<clock name=\"fpga$clknum\" driver_name=\"fpga$clknum\" rate=\"[$clk @CLKFREQUENCY]\"/>"
				lappend clocklist $clkname
			}
		}

		# find parameters and fill in missing values
		foreach prop [$device selectNodes .//property] {
			set name [$prop @name]
			set propnode [$out_doc createElement property]
			$propnode setAttribute name $name

			if {![$prop hasAttribute "value"]} {
				set modtype_pattern "XPAR_(.+)__(.+)"
				regexp $modtype_pattern $name dummy1 dummy2 param
				set param_node [$module selectNodes .//PARAMETER\[@NAME="C_$param"\]]
				$propnode setAttribute value [$param_node @VALUE]
			} else {
				$propnode setAttribute value [$prop @value]
			}

			$node appendChild $propnode
		}

		$out_node appendChild $node
	}
}


set output_fd [open $output w+]
puts $output_fd [$out_doc asXML]
close $output_fd

exit 0
