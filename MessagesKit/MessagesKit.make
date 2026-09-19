# Included by every in-tree consumer of MessagesKit (app, backends, tests,
# tools) so they build against the framework in this tree rather than a
# possibly stale installed copy.
MSGKIT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

ADDITIONAL_INCLUDE_DIRS += -I$(MSGKIT_DIR) -I$(MSGKIT_DIR)/derived_src
ADDITIONAL_LIB_DIRS += -L$(MSGKIT_DIR)/MessagesKit.framework
MSGKIT_LIBS = -lMessagesKit
