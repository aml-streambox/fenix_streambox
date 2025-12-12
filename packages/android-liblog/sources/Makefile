OUT_DIR ?= .

SO_VERSION = 1
SO_REALNAME = 1.0.0
LIBLOG_SRC_DIR ?= .
OBJC = $(OUT_DIR)/logd_write.o $(OUT_DIR)/logprint.o $(OUT_DIR)/event_tag_map.o $(OUT_DIR)/fake_log_device.o
CFLAGS += -fPIC -I$(LIBLOG_SRC_DIR)/include/
LDFLAGS += -L./lib -lglibc_bridge -lc++.so -lc++abi.so
TARGET=liblog.so
SONAME_TARGET=liblog.so.${SO_VERSION}
REAL_TARGET=liblog.so.${SO_REALNAME}

$(info "OUT_DIR : $(OUT_DIR)")
ifeq ($(USE_FAKE_DEVICE),y)
CFLAGS += -DFAKE_LOG_DEVICE
endif

# rules
all: $(TARGET) ${SONAME_TARGET} ${REAL_TARGET}

$(REAL_TARGET): $(OBJC)
	$(CC) -fPIC -g -shared -Wl,-soname,${SONAME_TARGET} -o $(OUT_DIR)/$@ $^

$(SONAME_TARGET): $(REAL_TARGET)
	ln -s $^ $(OUT_DIR)/$@

$(TARGET): $(SONAME_TARGET)
	ln -s $^ $(OUT_DIR)/$@

$(OUT_DIR)/%.o: %.c
	$(CC) -c $(CFLAGS) $< -o $@

.PHONY: clean

clean:
	rm -f $(OBJC) $(TARGET) ${SONAME_TARGET} ${REAL_TARGET} $(OUT_DIR)/$(TARGET)

install:
	install -m 755 $(OUT_DIR)/$(TARGET) $(STAGING_DIR)/usr/lib
	install -m 755 $(OUT_DIR)/$(TARGET) $(TARGET_DIR)/usr/lib
	install -m 755 $(OUT_DIR)/$(SONAME_TARGET) $(STAGING_DIR)/usr/lib
	install -m 755 $(OUT_DIR)/$(SONAME_TARGET) $(TARGET_DIR)/usr/lib
	install -m 755 $(OUT_DIR)/$(REAL_TARGET) $(STAGING_DIR)/usr/lib
	install -m 755 $(OUT_DIR)/$(REAL_TARGET) $(TARGET_DIR)/usr/lib
	mkdir -p $(STAGING_DIR)/usr/include/android
	mkdir -p $(STAGING_DIR)/usr/include/cutils
	install -m 755 $(LIBLOG_SRC_DIR)/include/android/*  $(STAGING_DIR)/usr/include/android/
	install -m 755 $(LIBLOG_SRC_DIR)/include/cutils/*  $(STAGING_DIR)/usr/include/cutils/
