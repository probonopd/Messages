GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../../MessagesKit/MessagesKit.make

BUNDLE_NAME = Nosterm
BUNDLE_EXTENSION = .msgbackend
Nosterm_PRINCIPAL_CLASS = NTNostermBackend
# Ships inside Messages.app/PlugIns (copied by the app's makefile), never on
# its own.
Nosterm_STANDARD_INSTALL = no

Nosterm_OBJC_FILES = $(wildcard Backend/*.m Protocol/*.m)

ADDITIONAL_INCLUDE_DIRS += -IBackend -IProtocol
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

Nosterm_BUNDLE_LIBS += $(MSGKIT_LIBS) -lcrypto

include $(GNUSTEP_MAKEFILES)/bundle.make
