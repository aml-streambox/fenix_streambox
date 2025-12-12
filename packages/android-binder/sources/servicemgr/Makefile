
BINDERSMR_SRC_DIR ?= $(shell pwd)
SRCS = $(wildcard *.c)
OBJS = $(patsubst %.c,%.o, $(SRCS))

CFLAGS += -I$(STAGING_DIR)/usr/include
LDFLAGS +=
TARGET=servicemanager

# rules
all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) $^ -o $@
	$(STRIP) $@

%.o: %.c
	$(CC) -c $(CFLAGS) $< -o $@

.PHONY: clean

clean:
	rm -f $(OBJS) $(TARGET)
	rm -rf $(STAGING_DIR)/usr/bin/$(TARGET)

install:
	install -m 755 $(TARGET) $(STAGING_DIR)/usr/bin
	install -m 755 $(TARGET) $(TARGET_DIR)/usr/bin
