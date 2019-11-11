#
# \brief  Print port hash
# \author Norman Feske
# \date   2018-11-13
#

default:

STRICT_HASH    ?= no
MSG_GENERATE   := true 
_DST_HASH_FILE := default
REDIR          :=

include $(PORT)
include $(PORTS_TOOL_DIR)/mk/hash.inc
