GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../MessagesKit/MessagesKit.make

LOUNGE_DIR = ../Backends/TheLounge

TOOL_NAME = thelounge-protocol-dump

thelounge-protocol-dump_OBJC_FILES = thelounge-protocol-dump/main.m \
    $(wildcard $(LOUNGE_DIR)/EngineIO/*.m) \
    $(wildcard $(LOUNGE_DIR)/SocketIO/*.m)

ADDITIONAL_CPPFLAGS += -I$(LOUNGE_DIR)/EngineIO -I$(LOUNGE_DIR)/SocketIO
# Model properties intentionally mirror wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

ADDITIONAL_TOOL_LIBS += $(MSGKIT_LIBS) -lcurl

include $(GNUSTEP_MAKEFILES)/tool.make