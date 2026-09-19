GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

include $(GNUSTEP_MAKEFILES)/common.make
include ../MessagesKit/MessagesKit.make

APP_NAME = BubbleDemo

BubbleDemo_OBJC_FILES = main.m ../Messages/Bubbles/MSGBubbleMessage.m \
                        ../Messages/Bubbles/MSGBubbleTheme.m \
                        ../Messages/Bubbles/MSGBubbleTranscriptView.m \
                        ../Messages/UI/MSGLinkDetector.m

ADDITIONAL_CPPFLAGS += -I$(CURDIR)/../Messages/Bubbles -I$(CURDIR)/../Messages/UI
# Zero-warning policy of the parent project applies here as well.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule
ADDITIONAL_GUI_LIBS += $(MSGKIT_LIBS)

include $(GNUSTEP_MAKEFILES)/application.make
