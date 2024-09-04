##
# Generic actions that do not require a project directory
#

namespace eval goa {
	namespace ensemble create

	namespace export help update depot-dir add-depot-user

	##
	# implements 'goa help'
	#
	proc help { help_topic } {

		global   tool_dir

		set file [file join $tool_dir doc $help_topic.txt]
		if {![file exists $file]} {
			set topics [glob -directory [file join $tool_dir doc] -tail *.txt]
			regsub -all {.txt} $topics "" topics
			exit_with_error "help topic '$help_topic' does not exist\n"\
			                "\n Available topics are: [join $topics {, }]\n"
		}
		set     cmd [file join $tool_dir gosh gosh]
		lappend cmd --style man $file | man -l -
		spawn -noecho sh -c "$cmd"
		interact
	}

	##
	# implements 'goa update-goa'
	#
	proc update { branch } {

		global   tool_dir

		set status [exec git -C [file dirname [file dirname $tool_dir]] status -s]
		if {$status != ""} {
			exit_with_error "aborting Goa update because it was changed locally\n\n$status" }

		if {[catch { goa_git fetch origin } msg]} {
			exit_with_error "Goa update could not fetch new version:\n$msg" }

		if {$branch != ""} {

			set remote_branches [avail_goa_branches]

			if {[lsearch $remote_branches $branch] == -1} {
				exit_with_error "Goa version $branch does not exist\n" \
				                "\n Available versions are: [join $remote_branches {, }]\n"
			}

			set git_branch_output [goa_git branch | sed "s/^..//"]
			set local_branches [split $git_branch_output "\n"]

			if {[lsearch $local_branches $branch] == -1} {
				goa_git checkout -q -b $branch origin/$branch
			} else {
				goa_git checkout -q $branch
			}
		}

		goa_git merge --ff-only origin/[current_goa_branch]
	}

	
	##
	# Return 1 if depot_dir exists
	#
	proc _depot_exists { } {

		global depot_dir
		return [expr {[file exists $depot_dir] && [file isdirectory $depot_dir]}]
	}


	##
	# Set writeable permission for specified path and its subdirectories
	#
	proc _make_writeable { path } {

		file attributes $path -permissions "+w"
		if {[file isdirectory $path]} {
			foreach entry [glob [file join $path "*"]] {
				_make_writeable $entry } }
	}

	##
	# Implements 'goa depot-dir'
	#
	proc depot-dir { } {

		global tool_dir
		global depot_dir

		# create default depot
		if {![_depot_exists]} {
			file mkdir [file dirname $depot_dir]
			file copy [file join $tool_dir default_depot] $depot_dir
			_make_writeable $depot_dir
		}
	}

	##
	# Implements 'goa add-depot-user'
	#
	proc add-depot-user { new_depot_user depot_url pubkey_file gpg_user_id } {

		global depot_dir

		set policy [depot_policy]

		set new_depot_user_dir [file join $depot_dir $new_depot_user]
		if {[file exists $new_depot_user_dir]} {
			if {$policy == "overwrite"} {
				file delete -force $new_depot_user_dir
			} elseif {$policy == "retain"} {
				log "depot user directory $new_depot_user_dir already exists"
				return
			} else {
				exit_with_error "depot user directory $new_depot_user_dir already exists\n" \
				                 "\n You may specify '--depot-overwrite' to replace" \
				                 "or '--depot-retain' to keep the existing directory.\n"
			}
		}

		file mkdir $new_depot_user_dir

		set fh [open [file join $new_depot_user_dir download] "WRONLY CREAT TRUNC"]
		puts $fh $depot_url
		close $fh

		set new_pubkey_file [file join $new_depot_user_dir pubkey]

		if {$pubkey_file != ""} {
			file copy $pubkey_file $new_pubkey_file }

		if {$gpg_user_id != ""} {
			exit_if_not_installed gpg
			if {[catch { exec gpg --armor --export $gpg_user_id > $new_pubkey_file } msg]} {
				file delete -force $new_depot_user_dir
				exit_with_error "exporting the public key from the GPG keyring failed\n$msg"
			}
		}
	}

}
