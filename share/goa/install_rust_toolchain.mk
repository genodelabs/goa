#!/usr/bin/make -f

#
# \brief  Install Rust toolchain via rustup
# \author Johannes Schlatow
# \date   2025-09-09
#

define HELP_MESSAGE

  Install rust toolchain.

  usage:

    $(firstword $(MAKEFILE_LIST)) (query|install) [VERSION=stable|nightly|...] [ARCH=x86_64|...]

endef

define NEWLINE


endef

DARK_COL    ?= \x1b[00;33m
DEFAULT_COL ?= \x1b[0m

ECHO    := echo -e
VERBOSE ?= @

# newer versions fail with unresolved symbol 'pthread_getthreadid_np'
VERSION ?= nightly-2025-08-07
ARCH    ?= x86_64

TOOLCHAIN := $(VERSION)-$(ARCH)-unknown-linux-gnu

.PHONY: query install

######################
# check dependencies #
######################

check_tool = $(if $(shell command -v $(1)),,$(error Need to have '$(1)' installed.))
$(call check_tool,rustup)

################################
# query version and components #
################################

usage:
	@$(ECHO) "$(subst $(NEWLINE),\n,$(HELP_MESSAGE))"

query:
	@$(ECHO) "$(DARK_COL)query$(DEFAULT_COL) $(TOOLCHAIN)"
	$(VERBOSE)rustup show | grep name | grep $(TOOLCHAIN) > /dev/null \
		|| (echo "$(TOOLCHAIN) is inactive" && exit 1)
	$(VERBOSE)rustup component list --toolchain $(TOOLCHAIN) | grep rust-src | grep installed > /dev/null \
		|| (echo "$(TOOLCHAIN is missing rust-src)" && exit 1)
	@$(ECHO) "$(DARK_COL)okay$(DEFAULT_COL) $(TOOLCHAIN)"

install:
	@$(ECHO) "$(DARK_COL)install$(DEFAULT_COL) $(TOOLCHAIN)"
	$(VERBOSE)rustup default $(TOOLCHAIN)
	$(VERBOSE)rustup install $(VERSION) --no-self-update
	$(VERBOSE)rustup component add rust-src --toolchain $(TOOLCHAIN)
	@$(ECHO) "$(DARK_COL)okay$(DEFAULT_COL) $(TOOLCHAIN)"
