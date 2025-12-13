AML_BUILD_DIR?=.

SRCS=src/primitives.c \
	src/resampler.c \
	src/speexresample/resample.c
SRCPPS = src/IpcBuffer/IpcBuffer.cpp

CUTILS_SRCS=src/cutils/strlcpy.c
CUTILS_SRCPPS = src/cutils/hashmap.cpp \
	src/cutils/properties.cpp \
	src/cutils/str_parms.cpp \
	src/cutils/threads.cpp

#Allow to configure NEON support of SPEEX
TOOLCHAIN_NEON_SUPPORT ?= y
ifeq ($(TOOLCHAIN_NEON_SUPPORT),y)
TOOLCHAIN_NEON_FLAGS = -mfpu=neon -D_USE_NEON
endif

CFLAGS+=-fPIC -O2 -I./include -I./include/speex -I./include/IpcBuffer -I. -I./src $(TOOLCHAIN_NEON_FLAGS) -DNDEBUG -DFIXED_POINT -DRESAMPLE_FORCE_FULL_SINC_TABLE -DEXPORT=
LDFLAGS+=-llog -ldl -lrt -lpthread -lstdc++

CUTILS_OBJCTS = $(patsubst %.c, $(AML_BUILD_DIR)/%.o, $(notdir $(CUTILS_SRCS)))
CUTILS_OBJCTS += $(patsubst %.cpp, $(AML_BUILD_DIR)/%.o, $(notdir $(CUTILS_SRCPPS)))
SRCS_OBJCTS = $(patsubst %.c, $(AML_BUILD_DIR)/%.o, $(notdir $(SRCS)))
SRCS_OBJCTS += $(patsubst %.cpp, $(AML_BUILD_DIR)/%.o, $(notdir $(SRCPPS)))
SRCS_DIR = $(dir $(SRCS) $(SRCPPS))
CUTILS_DIR = $(dir $(CUTILS_SRCS) $(SRCPPS))

vpath %.c $(SRCS_DIR):$(CUTILS_DIR)

$(AML_BUILD_DIR)/%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

$(AML_BUILD_DIR)/%.o: %.cc
	$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $<

vpath %.cpp $(SRCS_DIR):$(CUTILS_DIR)

$(AML_BUILD_DIR)/%.o: %.cpp
	$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $<

all: $(AML_BUILD_DIR)/libamaudioutils.so $(AML_BUILD_DIR)/libcutils.so

$(AML_BUILD_DIR)/libamaudioutils.so: $(SRCS_OBJCTS)
	$(CC) $(CFLAGS) -shared -o $@ $^ $(LDFLAGS)

$(AML_BUILD_DIR)/libcutils.so: $(CUTILS_OBJCTS)
	$(CC) $(CFLAGS) -shared -o $@ $^ $(LDFLAGS)

.PHONY: install
install:
	install -m 644 -D $(AML_BUILD_DIR)/libamaudioutils.so -t $(STAGING_DIR)/usr/lib
	install -m 644 -D $(AML_BUILD_DIR)/libamaudioutils.so -t $(TARGET_DIR)/usr/lib
	install -m 644 -D $(AML_BUILD_DIR)/libcutils.so -t $(STAGING_DIR)/usr/lib
	install -m 644 -D $(AML_BUILD_DIR)/libcutils.so -t $(TARGET_DIR)/usr/lib
	for f in $(@D)/include/audio_utils/*.h; do \
		install -m 644 -D $${f} -t $(STAGING_DIR)/usr/include/audio_utils; \
	done
	for f in $(@D)/include/IpcBuffer/*.h; do \
		install -m 644 -D $${f} -t $(STAGING_DIR)/usr/include/IpcBuffer; \
	done

.PHONY: clean
clean:
	rm -rf $(STAGING_DIR)/usr/include/audio_utils
	rm -rf $(STAGING_DIR)/usr/include/cutils
	rm -f $(AML_BUILD_DIR)/*.so
	rm -f $(AML_BUILD_DIR)/*.o
	rm -f $(TARGET_DIR)/usr/lib/libamaudioutils.so
	rm -f $(STAGING_DIR)/usr/lib/libamaudioutils.so

