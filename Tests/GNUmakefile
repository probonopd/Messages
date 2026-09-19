include $(GNUSTEP_MAKEFILES)/common.make

TEST_TOOL_NAME = t_accounts t_quassel t_model t_engineio t_socketio t_protocol t_session t_contextmenu \
                 t_bubbles t_badge t_nostr_crypto t_nosterm_live t_nosterm_catchup \
                 t_nosterm_cleanup t_nosterm_nickname t_nosterm_read

include ../MessagesKit/MessagesKit.make

LOUNGE_DIR = ../Backends/TheLounge
NOSTERM_DIR = ../Backends/Nosterm
QUASSEL_DIR = ../Backends/Quassel
APP_DIR = ../Messages

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework \
                       -I$(LOUNGE_DIR)/EngineIO -I$(LOUNGE_DIR)/SocketIO \
                       -I$(LOUNGE_DIR)/Protocol -I$(NOSTERM_DIR)/Protocol \
                       -I$(LOUNGE_DIR)/Backend -I$(NOSTERM_DIR)/Backend \
                       -I$(APP_DIR)/UI -I$(APP_DIR)/Bubbles
ADDITIONAL_TOOL_LIBS += $(MSGKIT_LIBS)
# Model properties intentionally mirror The Lounge wire field names
# (newNick, newIdent, newHost, rawText) which trigger the Cocoa ownership
# naming heuristic; the names are correct for this project.
ADDITIONAL_OBJCFLAGS += -Wno-objc-property-matches-cocoa-ownership-rule

# Model, logger, preferences and the WebSocket transport come from the
# MessagesKit framework; only backend and UI sources are compiled in.
MODEL_SRC =
SUPPORT_SRC =
EIO_SRC = $(LOUNGE_DIR)/EngineIO/TLEngineIOPacket.m $(LOUNGE_DIR)/EngineIO/TLEngineIOParser.m
SIO_SRC = $(LOUNGE_DIR)/SocketIO/TLSocketIOPacket.m $(LOUNGE_DIR)/SocketIO/TLSocketIOParser.m
PROTO_SRC = $(wildcard $(LOUNGE_DIR)/Protocol/*.m $(LOUNGE_DIR)/Backend/*.m \
            $(NOSTERM_DIR)/Protocol/*.m $(NOSTERM_DIR)/Backend/*.m)

t_model_OBJC_FILES = t_model.m $(MODEL_SRC)
t_accounts_OBJC_FILES = t_accounts.m

# The Quassel engine is ARC code; link the objects its bundle build made
# instead of recompiling them under this directory's manual retain/release.
t_quassel_OBJC_FILES = t_quassel.m $(wildcard $(QUASSEL_DIR)/Backend/*.m)
t_quassel_OBJ_FILES = $(addprefix $(QUASSEL_DIR)/Engine/,\
	$(shell cat $(QUASSEL_DIR)/Engine/obj/subproject.txt))
t_quassel_INCLUDE_DIRS = -I$(QUASSEL_DIR)/Backend -I$(QUASSEL_DIR)/Engine \
	-I$(QUASSEL_DIR)/Transport
t_quassel_TOOL_LIBS += -lz
t_engineio_OBJC_FILES = t_engineio.m $(EIO_SRC) $(SUPPORT_SRC)
t_socketio_OBJC_FILES = t_socketio.m $(SIO_SRC) $(SUPPORT_SRC) $(EIO_SRC)
t_protocol_OBJC_FILES = t_protocol.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m

t_protocol_TOOL_LIBS += -lcurl -lcrypto

t_session_OBJC_FILES = t_session.m $(PROTO_SRC) $(MODEL_SRC) $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_session_TOOL_LIBS += -lcurl -lcrypto

# The context menu builder is AppKit code; NSMenu/NSMenuItem work headless.
UI_SRC = $(APP_DIR)/UI/MSGContextMenuBuilder.m

t_contextmenu_OBJC_FILES = t_contextmenu.m $(UI_SRC) $(MODEL_SRC)
t_contextmenu_TOOL_LIBS += -lgnustep-gui

BUBBLE_SRC = $(APP_DIR)/Bubbles/MSGBubbleMessage.m $(APP_DIR)/Bubbles/MSGBubbleTheme.m \
             $(APP_DIR)/Bubbles/MSGBubbleTranscriptView.m

# The transcript view is AppKit code; NSView/NSTextStorage work headless.
t_bubbles_OBJC_FILES = t_bubbles.m $(BUBBLE_SRC) $(APP_DIR)/UI/MSGMessageRenderer.m \
            $(APP_DIR)/UI/MSGLinkDetector.m $(APP_DIR)/UI/MSGUserListView.m $(APP_DIR)/UI/MSGMessageView.m \
             $(MODEL_SRC)
t_bubbles_TOOL_LIBS += -lgnustep-gui

t_badge_OBJC_FILES = t_badge.m $(MODEL_SRC)
t_badge_TOOL_LIBS += -lgnustep-gui

t_nostr_crypto_OBJC_FILES = t_nostr_crypto.m $(NOSTERM_DIR)/Protocol/NTNostrCrypto.m
t_nostr_crypto_TOOL_LIBS += -lcrypto

# Live relay integration test. Reads TL_NOSTERM_TEST_KEY (and optionally
# TL_NOSTERM_TEST_RELAY) from the environment; SKIPs cleanly when unset.
t_nosterm_live_OBJC_FILES = t_nosterm_live.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_nosterm_live_TOOL_LIBS += -lcurl -lcrypto

# Offline catch-up test: a message posted by a second identity while the first
# is offline must replay on the first's reconnect. Same gating as the live test.
t_nosterm_catchup_OBJC_FILES = t_nosterm_catchup.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_nosterm_catchup_TOOL_LIBS += -lcurl -lcrypto

# Cleanup: deletes NIP-29 groups the test identity published on the relay, so
# repeated live runs do not leave "tltest-"/"catchup-" groups behind. Gated by
# TL_NOSTERM_TEST_KEY, same as the other live tests.
t_nosterm_cleanup_OBJC_FILES = t_nosterm_cleanup.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_nosterm_cleanup_TOOL_LIBS += -lcurl -lcrypto

# Offline nickname-resolution unit test: drives kind 0 metadata parsing and
# displayNameForPubkey: directly, no relay required.
t_nosterm_nickname_OBJC_FILES = t_nosterm_nickname.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_nosterm_nickname_TOOL_LIBS += -lcurl -lcrypto

# Read-only relay test: connects to #general and prints the last 3 messages.
t_nosterm_read_OBJC_FILES = t_nosterm_read.m $(PROTO_SRC) $(MODEL_SRC) \
            $(SIO_SRC) $(EIO_SRC) $(SUPPORT_SRC) \
            $(LOUNGE_DIR)/EngineIO/TLEngineIOClient.m $(LOUNGE_DIR)/SocketIO/TLSocketIOClient.m
t_nosterm_read_TOOL_LIBS += -lcurl -lcrypto

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/test-tool.make