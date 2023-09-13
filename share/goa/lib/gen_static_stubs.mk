#
# Create empty stub libraries
#
# LIBS             - list of requested library stubs
# ABI_DIR          - destination directory
# CROSS_DEV_PREFIX - tool-chain prefix
# CC_MARCH         - architecture-specific compiler arguments

STATIC_LIBS := $(addsuffix .a, $(addprefix $(ABI_DIR)/lib,$(LIBS)))

default: $(STATIC_LIBS)

$(ABI_DIR)/empty.c:
	touch $(ABI_DIR)/empty.c

$(ABI_DIR)/libutil.o:
	$(CROSS_DEV_PREFIX)g++ $(CFLAGS) $(CPP_FLAGS) $(CC_MARCH) -c $(RUST_COMPAT_LIB) -o $@

$(ABI_DIR)/%.o: $(ABI_DIR)/empty.c
	$(CROSS_DEV_PREFIX)gcc $(CC_MARCH) -c $< -o $@

$(ABI_DIR)/%.a: $(ABI_DIR)/%.o
	$(CROSS_DEV_PREFIX)ar rcs $@ $<
