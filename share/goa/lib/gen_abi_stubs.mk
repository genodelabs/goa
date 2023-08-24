#
# Rules to create ABI stub libraries from the symbol files found in the API
# archives.
#
# TOOL_DIR         - base directory of goa's tools
# APIS             - list of API archives
# ABI_DIR          - destination directory
# CROSS_DEV_PREFIX - tool-chain prefix
# ARCH             - CPU architecture
# LD_MARCH         - architecture-specific linker arguments
# CC_MARCH         - architecture-specific compiler arguments
#

SYMBOL_FILES := $(wildcard $(addsuffix /lib/symbols/*,$(addprefix $(DEPOT_DIR)/,$(APIS))))

# array to look up the symbol-file path for a given library name
$(foreach S,$(SYMBOL_FILES),$(eval SYMBOL_FILE(${notdir $S}) := $S))

ABIS := $(addsuffix .lib.so, $(addprefix $(ABI_DIR)/,$(notdir $(SYMBOL_FILES))))

SYMBOLS_NEW := $(addprefix $(ABI_DIR)/,$(addsuffix .symbols.s.new,$(notdir $(SYMBOL_FILES))))

default: $(SYMBOLS_NEW) $(ABIS)

# for GNU Make < 4.4, we need this rule for non-existing .symbols.s files
SYMBOLS        := $(addprefix $(ABI_DIR)/,$(addsuffix .symbols.s,$(notdir $(SYMBOL_FILES))))
SYMBOLS_NEXIST := $(filter-out $(wildcard $(SYMBOLS)),$(SYMBOLS))
$(SYMBOLS_NEXIST): $(ABI_DIR)/%.symbols.s: $(ABI_DIR)/%.symbols.s.new

ASM_SYM_DEPENDENCY := .long \1
ifeq ($(ARCH),x86_64)
ASM_SYM_DEPENDENCY := movq \1@GOTPCREL(%rip), %rax
endif

$(SYMBOLS_NEW): $(ABI_DIR)/%.symbols.s.new:
	mkdir -p $(dir $@)
	sed -e "s/^\(\w\+\) D \(\w\+\)\$$/.data; .global \1; .type \1,%object; .size \1,\2; \1:/p" \
	    -e "s/^\(\w\+\) V/.data; .weak \1; .type \1,%object; \1:/p" \
	    -e "s/^\(\w\+\) T/.text; .global \1; .type \1,%function; \1:/p" \
	    -e "s/^\(\w\+\) R \(\w\+\)\$$/.section .rodata; .global \1; .type \1,%object; .size \1,\2; \1:/p" \
	    -e "s/^\(\w\+\) W/.text; .weak \1; .type \1,%function; \1:/p" \
	    -e "s/^\(\w\+\) B \(\w\+\)\$$/.bss; .global \1; .type \1,%object; .size \1,\2; \1:/p" \
	    -e "s/^\(\w\+\) U/.text; .global \1; $(ASM_SYM_DEPENDENCY)/p" \
	    ${SYMBOL_FILE($*)} > $@
	if [ -f $(ABI_DIR)/$*.symbols.s ]; then \
		diff -q $@ $(ABI_DIR)/$*.symbols.s || rm $(ABI_DIR)/$*.symbols.s; \
	fi
	if [ ! -f $(ABI_DIR)/$*.symbols.s ]; then \
		cp $@ $(ABI_DIR)/$*.symbols.s; \
	fi
	rm $@

$(ABI_DIR)/%.symbols.o: $(ABI_DIR)/%.symbols.s
	$(CROSS_DEV_PREFIX)gcc $(CC_MARCH) -c $< -o $@

$(ABI_DIR)/%.lib.so: $(ABI_DIR)/%.symbols.o
	$(CROSS_DEV_PREFIX)ld -o $@ -soname $(notdir $@) -shared --eh-frame-hdr $(LD_MARCH) \
	                      -T $(TOOL_DIR)/ld/genode_rel.ld \
	                      $<
