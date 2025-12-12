LOCAL_PATH := $(shell pwd)
OUT_DIR ?= .

LOCAL_INCLUDES := -I. -Iinclude -I$(STAGING_DIR)/usr/include
LOCAL_LIBS := -L$(STAGING_DIR)/usr/lib -lpthread
LOCAL_DEFINES := -DHAVE_PTHREADS -DHAVE_ANDROID_OS=1

CFLAGS += -fPIC -Wall -Wno-unknown-pragmas -Wno-format -O3 -g -Wno-error=format-security
CFLAGS += $(LOCAL_INCLUDES) $(LOCAL_DEFINES) $(CFLAGS_EXTRA)

LDFLAGS += $(LOCAL_LIBS)
LDFLAGS += -L $(OUT_DIR)/

# binder src and obj
BINDER_CPP_SRCS := $(wildcard binder/*.cpp)
BINDER_CPP_SRCS += $(wildcard utils/*.cpp)
BINDER_C_SRCS := $(wildcard cutils/*.c)

BINDER_CPP_OBJS := $(patsubst %.cpp, %.lo, $(BINDER_CPP_SRCS))
BINDER_C_OBJS := $(patsubst %.c, %.o, $(BINDER_C_SRCS))
BINDER_OBJS := $(BINDER_C_OBJS) $(BINDER_CPP_OBJS)

# servicemanager src and obj
SVCMGR_SRCS := $(wildcard servicemgr/*.c)
SVCMGR_OBJS := $(patsubst %.c, %.o, $(SVCMGR_SRCS))


$(info "OUT_DIR : $(OUT_DIR)")
$(info "BINDER_OBJS : $(BINDER_OBJS)")
$(info "SVCMGR_OBJS : $(SVCMGR_OBJS)")

LOCAL_TARGETS := libbinder.so servicemanager
LOCAL_TARGETS_FULLPATH := $(patsubst %, $(OUT_DIR)/%, $(LOCAL_TARGETS))
$(info LOCAL_TARGETS_FULLPATH = $(LOCAL_TARGETS_FULLPATH))

.PHONY: all clean install
# rules
all: $(LOCAL_TARGETS)

libbinder.so: $(BINDER_OBJS)
	$(CXX) -shared -O3 -g $(LDFLAGS) $(patsubst %, $(OUT_DIR)/%, $^) -o $(OUT_DIR)/$@

servicemanager: $(SVCMGR_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) $(patsubst %, $(OUT_DIR)/%, $^) -o $(OUT_DIR)/$@

%.o: %.c
	$(CC) -c $(CFLAGS) $(LDFLAGS) $< -o $(OUT_DIR)/$@

%.lo: %.cpp
	$(CXX) -c $(CFLAGS) $(LDFLAGS) $< -o $(OUT_DIR)/$@

clean:
	rm -f $(OUT_DIR)/*.o $(OUT_DIR)/*.lo $(LOCAL_TARGETS_FULLPATH)
	rm -rf $(STAGING_DIR)/usr/include/libbinder
	rm -rf $(STAGING_DIR)/usr/lib/libbinder.so
	rm -rf $(TARGET_DIR)/usr/lib/libbinder.so
	rm -rf $(STAGING_DIR)/usr/bin/servicemanager
	rm -rf $(TARGET_DIR)/usr/bin/servicemanager

install:
	install -m 644 $(OUT_DIR)/libbinder.so $(STAGING_DIR)/usr/lib
	install -m 644 $(OUT_DIR)/libbinder.so $(TARGET_DIR)/usr/lib
	$(STRIP) $(TARGET_DIR)/usr/lib/libbinder.so
	mkdir -p $(STAGING_DIR)/usr/include/binder
	mkdir -p $(STAGING_DIR)/usr/include/utils
	install -m 644 $(LOCAL_PATH)/include/binder/*  $(STAGING_DIR)/usr/include/binder
	install -m 644 $(LOCAL_PATH)/include/utils/*  $(STAGING_DIR)/usr/include/utils
	install -m 755 $(OUT_DIR)/servicemanager $(STAGING_DIR)/usr/bin
	install -m 755 $(OUT_DIR)/servicemanager $(TARGET_DIR)/usr/bin
	$(STRIP) $(TARGET_DIR)/usr/bin/servicemanager
	install -m 755 $(LOCAL_PATH)/servicemgr/S52_binderSmr $(TARGET_DIR)/etc/init.d/S52_binderSmr

$(shell mkdir -p $(OUT_DIR)/binder $(OUT_DIR)/utils $(OUT_DIR)/cutils $(OUT_DIR)/servicemgr)
