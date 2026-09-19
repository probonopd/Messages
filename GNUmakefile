GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make

# The framework must build first: the backends and the app link against it,
# and the backends before the app, which copies them into its wrapper.
# Tests, Tools and BubbleDemo are developer-only and built from their own
# directories.
SUBPROJECTS = MessagesKit Backends Messages

include $(GNUSTEP_MAKEFILES)/aggregate.make
