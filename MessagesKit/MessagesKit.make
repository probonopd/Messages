# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

# Included by every in-tree consumer of MessagesKit (app, backends, tests,
# tools) so they build against the framework in this tree rather than a
# possibly stale installed copy.
MSGKIT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

ADDITIONAL_INCLUDE_DIRS += -I$(MSGKIT_DIR) -I$(MSGKIT_DIR)/derived_src
# By path, not -lMessagesKit: gnustep-make puts -L/System/Library/Libraries
# ahead of any -L added here, so once the framework is installed a plain -l
# links against the installed copy instead of the one just built.
MSGKIT_LIBS = $(MSGKIT_DIR)/MessagesKit.framework/Versions/Current/libMessagesKit.so
