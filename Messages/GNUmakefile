GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../MessagesKit/MessagesKit.make

APP_NAME = Messages

Messages_OBJC_FILES = $(wildcard App/*.m UI/*.m Bubbles/*.m)

# MessagesInfo.plist is picked up automatically by gnustep-make and merged
# into the generated Info.plist (see Instance/rules.make GNUSTEP_PLIST_DEPEND).
ADDITIONAL_INCLUDE_DIRS += -I$(CURDIR)/App -I$(CURDIR)/UI -I$(CURDIR)/Bubbles
# Model properties intentionally mirror wire field names (newNick, newIdent,
# newHost, rawText) which trigger the Cocoa ownership naming heuristic.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

ADDITIONAL_GUI_LIBS += $(MSGKIT_LIBS)

# App icon is placed in Resources/ of the .app bundle.
Messages_RESOURCE_FILES = Messages.png

include $(GNUSTEP_MAKEFILES)/application.make

# The backends live in the app wrapper where -[NSBundle builtInPlugInsPath]
# looks for them; installing the app installs them with it.
BACKEND_BUNDLES = $(wildcard ../Backends/*/*.msgbackend)

after-all::
	rm -rf $(APP_NAME).app/PlugIns
	mkdir -p $(APP_NAME).app/PlugIns
	$(foreach b,$(BACKEND_BUNDLES),cp -R $(b) $(APP_NAME).app/PlugIns/ &&) true
	rm -f $(APP_NAME).app/PlugIns/*.msgbackend/stamp.make
