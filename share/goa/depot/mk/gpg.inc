#
# \brief  Helper for using the GNU privacy guard
# \author Norman Feske
# \date   2017-03-27
#

# Allow the gpg command to be overridden on the command line
GPG ?= gpg

pubkey_filename = $(call archive_user,$1)/pubkey

pubkey_path = $(firstword \
                 $(wildcard $(addsuffix /$(call pubkey_filename,$1),$(DEPOT_DIR))) \
                 $(wildcard $(addsuffix /$(call pubkey_filename,$1), \
                               $(REP_SCULPT_DEPOT_DIRS))))

# obtain key ID of 'depot/<user>/pubkey' to be used to select signing key
pubkey_id = $(shell pubkey_file=$(call pubkey_path,$1); \
                    $(GPG) --dry-run --with-colon --import \
                           --import-options import-show $$pubkey_file 2> /dev/null |\
                    head -n 1 | cut -d: -f5)

MISSING_PUBKEY_FILES := $(sort \
                           $(foreach A,$(ARCHIVES),\
                              $(if $(call pubkey_path,$A),,\
                                 $(call archive_user,$A))))

missing_pubkey_files:
	@echo "Error: missing public-key files for:";\
	 for i in $(MISSING_PUBKEY_FILES); do echo "       $$i"; done; false

