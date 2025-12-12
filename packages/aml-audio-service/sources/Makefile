AML_BUILD_DIR?=.
VPATH:=src:src/binder:$(AML_BUILD_DIR)/src
PROTO_SRCS=audio_service.grpc.pb.cc audio_service.pb.cc
PROTO_OBJS=$(PROTO_SRCS:.cc=.o)

SHARED_BINDER_OBJS=src/binder/common.o

ifeq ($(use_binder),y)
SERVER_OBJS=src/audio_if.o src/binder/main_audio_service_binder.o src/binder/audio_service_binder.o src/binder/service_death_recipient.o
else
SERVER_OBJS=src/audio_server.o src/audio_if.o
endif

ifeq ($(rm_audioserver),y)
CLIENT_OBJS=src/audio_if.o
else
ifeq ($(use_binder),y)
CLIENT_OBJS=src/binder/audio_client_binder.o src/binder/audio_if_client_binder.o src/binder/client_death_recipient.o
CLIENT_OBJS+=$(SHARED_BINDER_OBJS)
else
CLIENT_OBJS=src/audio_client.o src/audio_if_client.o
CLIENT_OBJS+=$(PROTO_OBJS)
endif
endif
AMLAUDIOSET_OBJS = $(AML_BUILD_DIR)/AML_Audio_Setting.o

ifeq ($(use_binder),y)
SERVER_OBJS+=$(SHARED_BINDER_OBJS)
else
SERVER_OBJS+=$(PROTO_OBJS)
endif

TEST_PCM_OBJS=$(AML_BUILD_DIR)/test.o
TEST_DOLBY_OBJS=$(AML_BUILD_DIR)/test_ac3.o
TEST_HALPLAY_OBJS=$(AML_BUILD_DIR)/halplay.o
TEST_HALCAPTURE_OBJS=$(AML_BUILD_DIR)/hal_capture.o
TEST_AMLAUDIOHAL_OBJS=$(AML_BUILD_DIR)/test_amlaudiohal.o
TEST_AUDIOSET_OBJS=$(AML_BUILD_DIR)/test_audiosetting.o
TEST_MS12_OBJS=$(AML_BUILD_DIR)/dap_setting.o
TEST_SPEAKER_DELAY_OBJS=$(AML_BUILD_DIR)/speaker_delay.o
TEST_DIGITAL_MODE_OBJS=$(AML_BUILD_DIR)/digital_mode.o
TEST_ARC_TEST_OBJS=$(AML_BUILD_DIR)/test_arc.o
TEST_START_ARC_OBJS=$(AML_BUILD_DIR)/start_arc.o
TEST_HAL_PARAM_OBJS=$(AML_BUILD_DIR)/hal_param.o
TEST_HAL_DUMP_OBJS=$(AML_BUILD_DIR)/hal_dump.o
TEST_HAL_PATCH_OBJS=$(AML_BUILD_DIR)/hal_patch.o
TEST_MASTER_VOL_OBJS=$(AML_BUILD_DIR)/master_vol.o
EFFECT_TOOL_OBJS=$(AML_BUILD_DIR)/effect_tool.o $(AML_BUILD_DIR)/vx_v4_ctr.o
TEST_AUDIO_CLIENT_BINDER_OBJS=$(AML_BUILD_DIR)/audio_client_binder_test.o

PROTOC=$(HOST_DIR)/bin/protoc
PROTOC_INC=$(HOST_DIR)/include
GRPC_CPP_PLUGIN_PATH=$(HOST_DIR)/bin/grpc_cpp_plugin

CFLAGS += -Wall -fPIC -O2 -I$(PROTOC_INC) -I./include -I. -I./src -I$(AML_BUILD_DIR)/src -I$(AML_BUILD_DIR)
ifeq ($(aplugin),y)
	CFLAGS+= -DPIC
endif
CXXFLAGS += -Wall -std=c++14

ifeq ($(use_binder),y)
SC_LDFLAGS+=-Wl,--no-as-needed -lbinder -lboost_system -lamaudioutils -llog -ldl -lrt -lpthread -lstdc++ -pthread
LDFLAGS+= -Wl,--no-as-needed -lbinder -llog -ldl -lrt -lpthread -lstdc++ -pthread
else
SC_LDFLAGS+=-Wl,--no-as-needed -lgrpc++_unsecure -lprotobuf -lboost_system -lamaudioutils -llog -ldl -lrt -lpthread -lstdc++ -pthread
LDFLAGS+= -Wl,--no-as-needed -llog -ldl -lrt -lpthread -lstdc++ -pthread
endif

PROTO_SRCS_DIR = src/ $(AML_BUILD_DIR)/src/ src/binder/
INCLUDE_DIR = include/ $(AML_BUILD_DIR)/src

$(AML_BUILD_DIR)/%.grpc.pb.cc $(AML_BUILD_DIR)/%.grpc.pb.h: %.proto
	$(PROTOC) -I=. -I=$(PROTOC_INC) --grpc_out=$(AML_BUILD_DIR) --plugin=protoc-gen-grpc=$(GRPC_CPP_PLUGIN_PATH) $<

$(AML_BUILD_DIR)/%.pb.cc $(AML_BUILD_DIR)/%.pb.h: %.proto
	$(PROTOC) -I=. -I=$(PROTOC_INC) --cpp_out=$(AML_BUILD_DIR) --plugin=protoc-gen-grpc=$(GRPC_CPP_PLUGIN_PATH) $<

$(AML_BUILD_DIR)/%.pb.o: $(AML_BUILD_DIR)/src/%.pb.cc $(AML_BUILD_DIR)/src/%.pb.h | $(AML_BUILD_DIR)
	$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $<

$(AML_BUILD_DIR)/%.o: %.cpp | $(AML_BUILD_DIR)
	$(CC) -c $(CFLAGS) $(CXXFLAGS) -o $@ $<

$(AML_BUILD_DIR)/%.o: %.c | $(AML_BUILD_DIR)
	$(CC) -c $(CFLAGS) -o $@ $<

$(AML_BUILD_DIR)/src/audio_service.grpc.pb.cc: $(AML_BUILD_DIR)/src/audio_service.pb.h
audio_server.cpp: $(AML_BUILD_DIR)/src/audio_service.pb.h $(AML_BUILD_DIR)/src/audio_service.grpc.pb.cc
audio_client.cpp: $(AML_BUILD_DIR)/src/audio_service.pb.h $(AML_BUILD_DIR)/src/audio_service.grpc.pb.cc
audio_if_client.cpp: $(AML_BUILD_DIR)/src/audio_service.pb.h $(AML_BUILD_DIR)/src/audio_service.grpc.pb.cc

ifeq ($(rm_audioserver),y)
obj= libaudio_client.so libamlaudiosetting.so audio_client_test audio_client_test_ac3 halplay hal_capture dap_setting speaker_delay digital_mode test_arc start_arc hal_param hal_dump hal_patch master_vol test_audiosetting
else
ifeq ($(use_binder),y)
obj= audio_server libaudio_client.so audio_client_test audio_client_test_ac3 audio_client_binder_test halplay hal_capture dap_setting speaker_delay digital_mode test_arc start_arc hal_param hal_dump hal_patch master_vol effect_tool
else
obj= audio_server libaudio_client.so audio_client_test audio_client_test_ac3 halplay hal_capture dap_setting speaker_delay digital_mode test_arc start_arc hal_param hal_dump hal_patch master_vol effect_tool
endif
endif

ifeq ($(aplugin),y)
	obj+= libasound_module_pcm_ahal.so
endif

CLIENT_OBJS_BUILD = $(patsubst %.o, $(AML_BUILD_DIR)/%.o, $(notdir $(CLIENT_OBJS)))
SERVER_OBJS_BUILD = $(patsubst %.o, $(AML_BUILD_DIR)/%.o, $(notdir $(SERVER_OBJS)))
target_obj = $(addprefix $(AML_BUILD_DIR)/, $(obj))
$(info target_obj is ${target_obj})

vpath %.so $(AML_BUILD_DIR)

all:$(target_obj)

ifeq ($(rm_audioserver),y)
$(AML_BUILD_DIR)/libaudio_client.so: $(CLIENT_OBJS_BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -shared -o $@ $^

$(AML_BUILD_DIR)/libamlaudiosetting.so:$(AMLAUDIOSET_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -shared -o $@ $^

$(AML_BUILD_DIR)/test_audiosetting: $(TEST_AUDIOSET_OBJS) $(AML_BUILD_DIR)/libamlaudiosetting.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -lamlaudiosetting -o $@ $^
else
$(AML_BUILD_DIR)/audio_server: $(SERVER_OBJS_BUILD)
	$(CC) $(CFLAGS) $(SC_LDFLAGS) -o $@ $^

$(AML_BUILD_DIR)/libaudio_client.so: $(CLIENT_OBJS_BUILD)
	$(CC) $(CFLAGS) $(CXXFLAGS) $(SC_LDFLAGS) -shared -o $@ $^
endif

$(AML_BUILD_DIR)/libasound_module_pcm_ahal.so: $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(SC_LDFLAGS) -lasound -shared -L$(AML_BUILD_DIR) -laudio_client -o $@

$(AML_BUILD_DIR)/audio_client_test: $(TEST_PCM_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_PCM_OBJS)

$(AML_BUILD_DIR)/audio_client_test_ac3: $(TEST_DOLBY_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_DOLBY_OBJS)

$(AML_BUILD_DIR)/halplay: $(TEST_HALPLAY_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_HALPLAY_OBJS)

$(AML_BUILD_DIR)/hal_capture: $(TEST_HALCAPTURE_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_HALCAPTURE_OBJS)

$(AML_BUILD_DIR)/dap_setting: $(TEST_MS12_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_MS12_OBJS)

$(AML_BUILD_DIR)/speaker_delay: $(TEST_SPEAKER_DELAY_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_SPEAKER_DELAY_OBJS)

$(AML_BUILD_DIR)/digital_mode: $(TEST_DIGITAL_MODE_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_DIGITAL_MODE_OBJS)

$(AML_BUILD_DIR)/test_arc: $(TEST_ARC_TEST_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_ARC_TEST_OBJS)

$(AML_BUILD_DIR)/start_arc: $(TEST_START_ARC_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

$(AML_BUILD_DIR)/hal_param: $(TEST_HAL_PARAM_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_HAL_PARAM_OBJS)

$(AML_BUILD_DIR)/hal_dump: $(TEST_HAL_DUMP_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_HAL_DUMP_OBJS)

$(AML_BUILD_DIR)/hal_patch: $(TEST_HAL_PATCH_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_HAL_PATCH_OBJS)

$(AML_BUILD_DIR)/master_vol: $(TEST_MASTER_VOL_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_MASTER_VOL_OBJS)

$(AML_BUILD_DIR)/effect_tool: $(EFFECT_TOOL_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(EFFECT_TOOL_OBJS)

$(AML_BUILD_DIR)/audio_client_binder_test: $(TEST_AUDIO_CLIENT_BINDER_OBJS) $(AML_BUILD_DIR)/libaudio_client.so
	$(CC) $(CFLAGS) $(LDFLAGS) -L$(AML_BUILD_DIR) -laudio_client -o $@ $(TEST_AUDIO_CLIENT_BINDER_OBJS)

.PHONY: install
install:
ifneq ($(rm_audioserver),y)
	install -m 755 -D $(AML_BUILD_DIR)/audio_server -t $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/audio_client_test -t $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/audio_client_test_ac3 $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/effect_tool $(TARGET_DIR)/usr/bin/
else
	install -m 755 -D $(AML_BUILD_DIR)/test_audiosetting -t $(TARGET_DIR)/usr/bin/
	install -m 644 -D $(AML_BUILD_DIR)/libamlaudiosetting.so -t $(STAGING_DIR)/usr/lib/
	install -m 644 -D $(AML_BUILD_DIR)/libamlaudiosetting.so -t $(TARGET_DIR)/usr/lib/
	install -m 644 -D include/AML_Audio_Setting.h -t $(STAGING_DIR)/usr/include
endif
ifeq ($(use_binder),y)
	install -m 755 -D $(AML_BUILD_DIR)/audio_client_binder_test -t $(TARGET_DIR)/usr/bin/
endif
	install -m 755 -D $(AML_BUILD_DIR)/halplay $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/hal_capture $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/dap_setting $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/speaker_delay $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/digital_mode $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/test_arc $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/start_arc $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/hal_param $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/hal_dump $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/hal_patch $(TARGET_DIR)/usr/bin/
	install -m 755 -D $(AML_BUILD_DIR)/master_vol $(TARGET_DIR)/usr/bin/
	install -m 644 -D $(AML_BUILD_DIR)/libaudio_client.so -t $(TARGET_DIR)/usr/lib/
	install -m 644 -D $(AML_BUILD_DIR)/libaudio_client.so -t $(STAGING_DIR)/usr/lib/
ifeq ($(aplugin),y)
	install -m 644 -D $(AML_BUILD_DIR)/libasound_module_pcm_ahal.so -t $(TARGET_DIR)/usr/lib/alsa-lib/
endif
	install -m 644 -D include/audio_if_client.h -t $(STAGING_DIR)/usr/include
	install -m 644 -D include/audio_if.h -t $(STAGING_DIR)/usr/include
	install -m 644 -D include/audio_effect_if.h -t $(STAGING_DIR)/usr/include
	install -m 644 -D include/audio_effect_params.h -t $(STAGING_DIR)/usr/include

.PHONY: clean
clean:
	rm -f $(AML_BUILD_DIR)/audio_server
	rm -f $(AML_BUILD_DIR)/audio_client_test
	rm -f $(AML_BUILD_DIR)/audio_client_test_ac3
ifeq ($(use_binder),y)
	rm -f $(AML_BUILD_DIR)/audio_client_binder_test
endif
	rm -f $(AML_BUILD_DIR)/*.o
	rm -f $(AML_BUILD_DIR)/halplay
	rm -f $(AML_BUILD_DIR)/hal_capture
	rm -f $(AML_BUILD_DIR)/test_arc
	rm -f $(AML_BUILD_DIR)/start_arc
	rm -f $(AML_BUILD_DIR)/hal_param
	rm -f $(AML_BUILD_DIR)/hal_dump
	rm -f $(AML_BUILD_DIR)/hal_patch
	rm -f $(AML_BUILD_DIR)/master_vol
	rm -f $(AML_BUILD_DIR)/effect_tool
	rm -f $(AML_BUILD_DIR)/libaudio_client.so
	rm -f $(TARGET_DIR)/usr/bin/audio_server
	rm -f $(TARGET_DIR)/usr/bin/audio_client_test
	rm -f $(TARGET_DIR)/usr/bin/audio_client_test_ac3
ifeq ($(use_binder),y)
	rm -f $(TARGET_DIR)/usr/bin/audio_client_binder_test
endif
	rm -f $(TARGET_DIR)/usr/bin/halplay
	rm -f $(TARGET_DIR)/usr/bin/hal_capture
	rm -f $(TARGET_DIR)/usr/bin/speaker_delay
	rm -f $(TARGET_DIR)/usr/bin/digital_mode
	rm -f $(TARGET_DIR)/usr/bin/test_arc
	rm -f $(TARGET_DIR)/usr/bin/start_arc
	rm -f $(TARGET_DIR)/usr/bin/hal_param
	rm -f $(TARGET_DIR)/usr/bin/hal_dump
	rm -f $(TARGET_DIR)/usr/bin/hal_patch
	rm -f $(TARGET_DIR)/usr/bin/master_vol
	rm -f $(TARGET_DIR)/usr/bin/effect_tool
	rm -f $(TARGET_DIR)/usr/lib/libaudio_client.so
	rm -f $(STAGING_DIR)/usr/lib/libaudio_client.so
	rm -f $(STAGING_DIR)/usr/include/audio_if_client.h
	rm -f $(STAGING_DIR)/usr/include/audio_effect_if.h
	rm -f $(STAGING_DIR)/usr/include/audio_effect_params.h
