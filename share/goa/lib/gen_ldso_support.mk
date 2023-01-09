#
# Rules to create `ldso_so_support.lib.a`. This is provided by the `abi/base` depot archive.
# It is needed to build shared libraries.
#
# TOOL_DIR         - base directory of goa's tools
# APIS             - list of API archives
# ABI_DIR          - destination directory
# CROSS_DEV_PREFIX - tool-chain prefix
# CC_MARCH         - architecture-specific compiler arguments
#

C_FILE   := $(wildcard $(addsuffix /src/lib/ldso/so_support.c,$(addprefix $(DEPOT_DIR)/,$(APIS))))
O_FILE   := $(ABI_DIR)/so_support.o

MK_FILES := $(notdir $(wildcard $(addsuffix /lib/mk/ldso*.mk,$(addprefix $(DEPOT_DIR)/,$(APIS)))))
ABIS     := $(addsuffix .lib.a, $(basename $(addprefix $(ABI_DIR)/, $(MK_FILES))))

default: $(ABIS)

$(O_FILE): $(C_FILE)
	@echo "$(CROSS_DEV_PREFIX)gcc $(CC_MARCH) -c $< -o $@"
	$(CROSS_DEV_PREFIX)gcc $(CC_MARCH) -fPIC -c $< -o $@

$(ABIS): $(O_FILE)
	@echo "$(CROSS_DEV_PREFIX)ar -rcs $@ $<"
	$(CROSS_DEV_PREFIX)ar -rcs $@ $<

# vim : ft=mk
