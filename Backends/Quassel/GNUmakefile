GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../../MessagesKit/MessagesKit.make

BUNDLE_NAME = Quassel
BUNDLE_EXTENSION = .msgbackend
Quassel_PRINCIPAL_CLASS = QuasselBackend
# Ships inside Messages.app/PlugIns (copied by the app's makefile), never on
# its own.
Quassel_STANDARD_INSTALL = no

# The upstream engine is built separately with ARC (see Engine/GNUmakefile);
# the glue in Backend/ follows the rest of Messages and is manual
# retain/release.
Quassel_SUBPROJECTS = Engine
Quassel_OBJC_FILES = $(wildcard Backend/*.m)

ADDITIONAL_INCLUDE_DIRS += -IBackend -IEngine -ITransport
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

Quassel_BUNDLE_LIBS += $(MSGKIT_LIBS) -lz

include $(GNUSTEP_MAKEFILES)/bundle.make
