GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../../MessagesKit/MessagesKit.make

BUNDLE_NAME = TheLounge
BUNDLE_EXTENSION = .msgbackend
TheLounge_PRINCIPAL_CLASS = TLoungeBackend
# Ships inside Messages.app/PlugIns (copied by the app's makefile), never on
# its own.
TheLounge_STANDARD_INSTALL = no

TheLounge_OBJC_FILES = $(wildcard Backend/*.m Protocol/*.m SocketIO/*.m EngineIO/*.m)

ADDITIONAL_INCLUDE_DIRS += -IBackend -IProtocol -ISocketIO -IEngineIO
# Model properties intentionally mirror wire field names (newNick, newIdent,
# newHost, rawText) which trigger the Cocoa ownership naming heuristic.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

TheLounge_BUNDLE_LIBS += $(MSGKIT_LIBS) -lcurl

include $(GNUSTEP_MAKEFILES)/bundle.make
