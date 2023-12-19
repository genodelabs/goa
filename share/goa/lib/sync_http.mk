#!/usr/bin/make -f

#
# \brief  Sync files via HTTP PUT
# \author Johannes Schlatow
# \date   2023-12-19
#

define HELP_MESSAGE

  Sync files from SRC_DIR to SERVER via HTTP PUT. TMP_DIR is used for storing
  etags. You may provide DELETE=1 to remove the files from SERVER.

  usage:

    $(firstword $(MAKEFILE_LIST)) <file>... SRC_DIR=<path> TMP_DIR=<path> SERVER=<url> {DELETE=1}

endef

define NEWLINE


endef

DARK_COL    ?= \x1b[00;33m
DEFAULT_COL ?= \x1b[0m

ECHO    := echo -e
VERBOSE ?= @


.PHONY: delete upload missing_files missing_tmp_dir missing_server missing_src_dir

######################
# check dependencies #
######################

check_tool = $(if $(shell command -v $(1)),,$(error Need to have '$(1)' installed.))
$(call check_tool,curl)

######################
# check command line #
######################

usage:
	@$(ECHO) "$(subst $(NEWLINE),\n,$(HELP_MESSAGE))"

ifeq ($(TMP_DIR),)
$(MAKECMDGOALS): missing_tmp_dir
endif

ifeq ($(SERVER),)
$(MAKECMDGOALS): missing_server
endif

ifeq ($(SRC_DIR),)
ifeq ($(DELETE),)
$(MAKECMDGOALS): missing_src_dir
endif
endif

missing_tmp_dir: usage
	@$(ECHO) "Error: missing definition of TMP_DIR"; false

missing_server: usage
	@$(ECHO) "Error: missing definition of SERVER"; false

missing_src_dir: usage
	@$(ECHO) "Error: missing definition of SRC_DIR"; false

###########################
# check for missing files #
###########################

FILES_MISSING := $(sort $(foreach F, $(MAKECMDGOALS),\
                           $(if $(wildcard $(addprefix $(SRC_DIR)/,$F)),,$F)))

missing_files:
	@$(ECHO) "Error: missing files in $(SRC_DIR)";\
		for i in $(FILES_MISSING); do $(ECHO) "       $$i"; done; false

ifneq ($(DELETE),)
$(MAKECMDGOALS): %: delete_%
else ifneq ($(FILES_MISSING),)
$(MAKECMDGOALS): missing_files
else
$(MAKECMDGOALS): %: upload_%
endif

TARGETS := $(MAKECMDGOALS)
TARGETS_ETAG := $(abspath $(addprefix $(TMP_DIR)/,$(addsuffix .local.etag, $(TARGETS))))

.NOTINTERMEDIATE: $(TARGETS_ETAG)

# create TMP_DIR
$(TMP_DIR):
	$(VERBOSE)mkdir -p $(TMP_DIR)

# upload target file and update .local.etag if the former is newer
$(abspath $(TMP_DIR)/%.local.etag): $(SRC_DIR)/% | $(TMP_DIR)
	$(VERBOSE)curl -s -T $< $(SERVER) && $(ECHO) "$(DARK_COL)uploaded$(DEFAULT_COL) $* (local change)"
	$(VERBOSE)curl -s -o /dev/null --etag-save $@ $(SERVER)/$*

# first upload local changes (prerequisites) then perform conditional upload
upload_%: $(abspath $(TMP_DIR)/%.local.etag)
	$(VERBOSE)(curl -s --fail -T $(abspath $(SRC_DIR)/$*) --etag-compare $< $(SERVER) \
		&& curl -s -o /dev/null --etag-save $< $(SERVER)/$* \
		&& $(ECHO) "$(DARK_COL)uploaded$(DEFAULT_COL) $* (remote change)") || true

# delete from server
delete_%:
	$(VERBOSE)curl -f -s -X "DELETE" $(SERVER)/$* && $(ECHO) "$(DARK_COL)deleted$(DEFAULT_COL) $*" || true
