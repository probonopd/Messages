# Upstream iQuassel protocol engine and its GNUstep socket (GPL-3.0). Built
# as a subproject so it keeps its own memory model: upstream is written for
# ARC, the rest of Messages is manual retain/release.
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = Engine

Engine_OBJC_FILES = $(wildcard *.m) $(wildcard ../Transport/*.m)

ADDITIONAL_INCLUDE_DIRS += -I../Transport
ADDITIONAL_OBJCFLAGS += -fobjc-arc -include QuasselCompat.h

include $(GNUSTEP_MAKEFILES)/subproject.make
