# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = MessagesKit
MessagesKit_CURRENT_VERSION_NAME = 0

MessagesKit_OBJC_FILES = $(wildcard *.m)
MessagesKit_HEADER_FILES = $(wildcard *.h)

# Model properties intentionally mirror wire field names (newNick, newIdent,
# newHost, rawText) which trigger clang's ownership naming heuristic.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

MessagesKit_LIBRARIES_DEPEND_UPON += -lcurl $(FND_LIBS) $(OBJC_LIBS)

include $(GNUSTEP_MAKEFILES)/framework.make
