#!/usr/bin/make -f

#
# \brief  Download and squash Genode tools
# \author Johannes Schlatow
# \date   2024-09-25
#

define HELP_MESSAGE

  Downloads a particular tool archive and creates squashfs.

  usage:

    $(firstword $(MAKEFILE_LIST)) <tool> INSTALL_DIR=<path>

endef

define NEWLINE


endef

DARK_COL    ?= \x1b[00;33m
DEFAULT_COL ?= \x1b[0m

ECHO    := echo -e
VERBOSE ?= @


.PHONY: missing_install_dir DUMMY

#################################
# Available tools and checksums #
#################################

TOOLS := genode-toolchain-23.05

URL(genode-toolchain-23.05) := https://github.com/genodelabs/genode/releases/download/23.05/genode-toolchain-23.05.tar.xz
SHA(genode-toolchain-23.05) := 880886efba0f592a3d3c5ffb9fa63e692cb6bd643e13c5c468d0da027c22716e

######################
# check dependencies #
######################

check_tool = $(if $(shell command -v $(1)),,$(error Need to have '$(1)' installed.))
$(call check_tool,curl)
$(call check_tool,xzcat)
$(call check_tool,sqfstar)

######################
# check command line #
######################

usage:
	@$(ECHO) "$(subst $(NEWLINE),\n,$(HELP_MESSAGE))"
	@$(ECHO) ""
	@$(ECHO) "Available tools: $(TOOLS)"

ifeq ($(INSTALL_DIR),)
$(MAKECMDGOALS): missing_install_dir
endif

missing_install_dir: usage
	@$(ECHO) "Error: missing definition of INSTALL_DIR"; false

TOOL_NAME     := $(firstword $(MAKECMDGOALS))

tool_unknown: usage
	@$(ECHO) "Error: tool $(TOOL_NAME) is unknown"; false

ifeq ($(filter $(TOOL_NAME),$(TOOLS)),)
$(MAKECMDGOALS): tool_unknown
endif

TOOL_DOWNLOAD := $(addprefix $(INSTALL_DIR),/download/$(notdir $(URL($(TOOL_NAME)))))
TOOL_SQUASHFS := $(addprefix $(INSTALL_DIR),/download/$(TOOL_NAME).squashfs)

# phony dummy target to suppress "nothing to be done" message
DUMMY:
	@:

$(TOOL_NAME): DUMMY $(TOOL_SQUASHFS)

$(dir $(TOOL_DOWNLOAD)):
	$(VERBOSE)mkdir -p $@

$(TOOL_DOWNLOAD): | $(dir $(TOOL_DOWNLOAD))
	@$(ECHO) "$(DARK_COL)download$(DEFAULT_COL) $(TOOL_NAME)"
	$(VERBOSE)\
		curl -s -o $@ -L $(URL($(TOOL_NAME))) || \
			($(ECHO) Error: Download for $(@F) failed; rm -f $@; false)
	$(VERBOSE)\
		cd $(dir $(TOOL_DOWNLOAD)); \
		($(ECHO) "$(SHA($(TOOL_NAME)))  $(@F)" |\
		sha256sum -c > /dev/null 2> /dev/null) || \
			($(ECHO) Error: Hash sum check for $(@F) failed; rm $@; false)

$(TOOL_SQUASHFS): $(TOOL_DOWNLOAD)
	@$(ECHO) "$(DARK_COL)squashing$(DEFAULT_COL) $(TOOL_NAME)"
	$(VERBOSE)xzcat $(TOOL_DOWNLOAD) | sqfstar -quiet -force -comp zstd $@
