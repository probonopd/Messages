# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../MessagesKit/MessagesKit.make

APP_NAME = Messages

Messages_OBJC_FILES = $(wildcard App/*.m UI/*.m Bubbles/*.m)

# MessagesInfo.plist is picked up automatically by gnustep-make and merged
# into the generated Info.plist (see Instance/rules.make GNUSTEP_PLIST_DEPEND).
ADDITIONAL_INCLUDE_DIRS += -I$(CURDIR)/App -I$(CURDIR)/UI -I$(CURDIR)/Bubbles
# Model properties intentionally mirror wire field names (newNick, newIdent,
# newHost, rawText) which trigger clang's ownership naming heuristic.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

ADDITIONAL_GUI_LIBS += $(MSGKIT_LIBS)

# App icon is placed in Resources/ of the .app bundle.
Messages_RESOURCE_FILES = Messages.png ../LICENSE

include $(GNUSTEP_MAKEFILES)/application.make

# The backends live in the app wrapper where -[NSBundle builtInPlugInsPath]
# looks for them. The build copies them into the wrapper in the tree so the
# uninstalled app runs; `make install` then installs them from the backend
# directories into the installed wrapper. The in-tree copy is skipped as
# root because `sudo make install` reruns `all`, and root-owned files in the
# tree would make the next build as the user fail.
BACKEND_BUNDLES = $(wildcard ../Backends/*/*.msgbackend)

copy-backends = rm -rf $(1)/PlugIns && mkdir -p $(1)/PlugIns && \
	for b in $(BACKEND_BUNDLES); do cp -R $$b $(1)/PlugIns/ || exit 1; done && \
	rm -f $(1)/PlugIns/*.msgbackend/stamp.make

after-all::
	if [ "$$(id -u)" != 0 ]; then $(call copy-backends,$(APP_NAME).app); fi

after-install::
	$(call copy-backends,$(GNUSTEP_APPS)/$(APP_NAME).app)
