// Copyright 2023 Amlogic, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <functional>

#include "audio_service_binder.h"
#include "service_death_recipient.h"

#include <IpcBuffer/audio_server_shmem.h>
#include <IpcBuffer/IpcBuffer.h>
#include <boost/interprocess/managed_shared_memory.hpp>

#define CHKP_AND_RET(p, r) do { if (!(p)) return (r); } while (0)

std::mutex AudioServiceBinder::gc_map_mutex_;

AudioServiceBinder* AudioServiceBinder::mInstance = nullptr;

AudioServiceBinder* AudioServiceBinder::GetInstance() {
    audio_server_shmem::getInstance(true);
    if (mInstance == nullptr) {
        mInstance = new AudioServiceBinder();
    }

    return mInstance;
}

AudioServiceBinder::AudioServiceBinder() {
    if (audio_hw_load_interface(&dev_) == 0) {
        if (dev_) {
            std::cout<< PROCESS_NAME_LOG << " Got audio hal interface successfully." << std::endl;
            effect_ = reinterpret_cast<audio_effect_t*>(dev_->common.reserved[0]);
        }
    }
}

AudioServiceBinder::~AudioServiceBinder() {
    for (std::unordered_set<audio_patch_handle_t>::const_iterator it = audioPatchHandles.begin(); it != audioPatchHandles.end(); ++it) {
        audio_patch_handle_t patch = *it;
        Device_release_audio_patch(patch);
    }

    audioPatchHandles.clear();

    if (dev_) {
        if (effect_) {
            effect_ = nullptr;
        }
        audio_hw_unload_interface(dev_);
        dev_ = nullptr;
    }
}

void AudioServiceBinder::on_client_turned_off(int clientPid) {
    std::lock_guard<std::mutex> lock(gc_map_mutex_);

    std::unordered_map<int, gc_stream_map_t>::iterator gc_map_it = gc_stream_map_.find(clientPid);
    if (gc_map_it == gc_stream_map_.end()) {
        std::cout << PROCESS_NAME_LOG << " Could not find entry with pid " << clientPid << " in garbage collection stream map." << std::endl;
        return;
    }

    gc_stream_map_t gc_stream_map_pair = gc_map_it->second;

    ::android::sp<ServiceDeathRecipient> serviceDeathRecipient = gc_stream_map_pair.first;
    if (serviceDeathRecipient != nullptr) serviceDeathRecipient.clear();

    std::unordered_map<std::string, stream_data_t>& streamsInfo = gc_stream_map_pair.second;
    stream_gc_(streamsInfo);
    streamsInfo.clear();

    gc_stream_map_.erase(gc_map_it);
}

int AudioServiceBinder::Device_common_close() {
    CHKP_AND_RET(dev_, -1);
    return dev_->common.close(&dev_->common);
}

int AudioServiceBinder::Device_init_check() {
    CHKP_AND_RET(dev_, -1);
    return dev_->init_check(dev_);
}

int AudioServiceBinder::Device_set_voice_volume(float volume) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_voice_volume(dev_, volume);
}

int AudioServiceBinder::Device_set_master_volume(float volume) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_master_volume(dev_, volume);
}

int AudioServiceBinder::Device_get_master_volume(float& masterVolume) {
    CHKP_AND_RET(dev_, -1);
    float vol = 0.0;
    int ret = dev_->get_master_volume(dev_, &vol);
    masterVolume = vol;
    return ret;
}

int AudioServiceBinder::Device_set_mode(audio_mode_t mode) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_mode(dev_, mode);
}

int AudioServiceBinder::Device_set_mic_mute(bool state) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_mic_mute(dev_, state);
}

int AudioServiceBinder::Device_get_mic_mute(bool& state) {
    CHKP_AND_RET(dev_, -1);
    return dev_->get_mic_mute(dev_, &state);
}

int AudioServiceBinder::Device_set_parameters(const char* kv_pairs) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_parameters(dev_, kv_pairs);
}

char* AudioServiceBinder::Device_get_parameters(const char* keys) {
    CHKP_AND_RET(dev_, nullptr);
    return dev_->get_parameters(dev_, keys);
}

int AudioServiceBinder::Device_get_input_buffer_size(const struct audio_config& config) {
    CHKP_AND_RET(dev_, -1);
    return dev_->get_input_buffer_size(dev_, &config);
}

int AudioServiceBinder::Device_open_output_stream(::android::sp<::android::IBinder> audioClientBinder,
                                            int seq,
                                            audio_io_handle_t handle,
                                            audio_devices_t devices,
                                            audio_output_flags_t flags,
                                            struct audio_config& config,
                                            const char* address,
                                            int& clientId,
                                            struct audio_stream*& stream_hw,
                                            audio_stream_out_info_t*& stream_out_info) {
    CHKP_AND_RET(dev_, -1);

    stream_out_info = new audio_stream_out_info_t;
    if (!stream_out_info) return -ENOMEM;

    stream_out_info->shm = nullptr;

    int client_id = ::android::IPCThreadState::self()->getCallingPid();
    if (client_id < 0) {
        clientId = -1;
        return -1;
    }

    char buf[32];
    snprintf(buf, sizeof(buf), "%d-%d", client_id, seq);
    std::string stream_id(buf);

    struct audio_stream_out* stream = nullptr;

    int ret = dev_->open_output_stream(dev_, handle, devices, flags, &config, &stream, address);
    clientId = client_id;

    if (stream) {
        stream_hw = &(stream->common);

        const char* stream_id_c_str = stream_id.c_str();
        if (updateStreamOutInfo(stream_id_c_str, stream, stream_out_info) == -1) return -1;

        std::cout << PROCESS_NAME_LOG << " open " << OUTPUT_STREAM_LABEL << " " << stream_id_c_str << std::endl;

        update_gc_stream_map(audioClientBinder, client_id, stream_id, AUDIO_STREAM_OUT, stream_out_info);
    }

    return ret;
}

void AudioServiceBinder::Device_close_output_stream(audio_stream_out_info_t* stream_out_info) {
    const char* name = stream_out_info->name;
    const std::string nameStr(name);

    {
        std::lock_guard<std::mutex> lock(stream_out_info->stream_mutex);
        posixUnmapDataCloseFileAndUnlinkName(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, name, stream_out_info->shm, KSHAREDBUFFERSIZE, stream_out_info->fd);
    }

    struct audio_stream_out* stream_out_hw = stream_out_info->stream_out_hw;
    if (dev_ && stream_out_hw) {
        std::cout << PROCESS_NAME_LOG << " close " << OUTPUT_STREAM_LABEL << " " << name << std::endl;
        dev_->close_output_stream(dev_, stream_out_hw);
    }

    int client_id = ::android::IPCThreadState::self()->getCallingPid();
    remove_stream_info_from_gc_stream_map(client_id, nameStr);

    if (stream_out_info != nullptr) {
        delete stream_out_info;
    }
}

int AudioServiceBinder::Device_open_input_stream(::android::sp<::android::IBinder> audioClientBinder,
                                            int seq,
                                            audio_io_handle_t handle,
                                            audio_devices_t devices,
                                            struct audio_config& config,
                                            audio_input_flags_t flags,
                                            const char* address,
                                            audio_source_t source,
                                            int& clientId,
                                            struct audio_stream*& stream_hw,
                                            audio_stream_in_info_t*& stream_in_info) {
    CHKP_AND_RET(dev_, -1);

    stream_in_info = new audio_stream_in_info_t;
    if (!stream_in_info) return -ENOMEM;

    stream_in_info->shm = nullptr;

    int client_id = ::android::IPCThreadState::self()->getCallingPid();
    if (client_id < 0) {
        clientId = -1;
        return -1;
    }
    char buf[32];
    snprintf(buf, sizeof(buf), "%d-%d", client_id, seq);
    std::string stream_id(buf);

    struct audio_stream_in* stream = nullptr;

    int ret = dev_->open_input_stream(dev_, handle, devices, &config, &stream, flags, address, source);
    clientId = client_id;

    if (stream) {
        stream_hw = &(stream->common);

        const char* stream_id_c_str = stream_id.c_str();
        if (updateStreamInInfo(stream_id_c_str, stream, stream_in_info) == -1) return -1;

        std::cout << PROCESS_NAME_LOG << " open " << INPUT_STREAM_LABEL << " " << stream_id_c_str << std::endl;

        update_gc_stream_map(audioClientBinder, client_id, stream_id, AUDIO_STREAM_IN, stream_in_info);
    }

    return ret;
}

void AudioServiceBinder::Device_close_input_stream(audio_stream_in_info_t* stream_in_info) {
    const char* name = stream_in_info->name;
    const std::string nameStr(name);

    {
        std::lock_guard<std::mutex> lock(stream_in_info->stream_mutex);
        posixUnmapDataCloseFileAndUnlinkName(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, name, stream_in_info->shm, KSHAREDBUFFERSIZE, stream_in_info->fd);
    }

    struct audio_stream_in* stream_in_hw = stream_in_info->stream_in_hw;
    if (dev_ && stream_in_hw) {
        std::cout << PROCESS_NAME_LOG << " close " << INPUT_STREAM_LABEL << " " << name << std::endl;
        dev_->close_input_stream(dev_, stream_in_hw);
    }

    int client_id = ::android::IPCThreadState::self()->getCallingPid();
    remove_stream_info_from_gc_stream_map(client_id, nameStr);

    if (stream_in_info != nullptr) {
        delete stream_in_info;
    }
}

int AudioServiceBinder::Device_dump(std::string& deviceDump) {
    int ret = -1;

    CHKP_AND_RET(dev_, ret);

    char* param = dev_->dump(dev_, 0);
    ret = param ? 0 : -1;

    deviceDump = std::string(param);

    // param is heap allocated and need free
    free(param);

    return ret;
}

int AudioServiceBinder::Device_set_master_mute(bool mute) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_master_mute(dev_, mute);
}

int AudioServiceBinder::Device_get_master_mute(bool& mute) {
    CHKP_AND_RET(dev_, -1);
    return dev_->get_master_mute(dev_, &mute);
}

int AudioServiceBinder::Device_create_audio_patch(unsigned int num_sources,
                                                const struct audio_port_config* sources,
                                                unsigned int num_sinks,
                                                const struct audio_port_config* sinks,
                                                audio_patch_handle_t& handle) {
    CHKP_AND_RET(dev_, -1);

    handle = (audio_patch_handle_t) (-1);

    int ret = dev_->create_audio_patch(dev_, num_sources, sources, num_sinks, sinks, &handle);
    if (ret == 0) {
        audioPatchHandles.insert(handle);
    }
    return ret;
}

int AudioServiceBinder::Device_release_audio_patch(audio_patch_handle_t handle) {
    CHKP_AND_RET(dev_, -1);

    int ret = dev_->release_audio_patch(dev_, handle);
    if (ret == 0) {
        audioPatchHandles.erase(handle);
    }
    return ret;
}

int AudioServiceBinder::Device_set_audio_port_config(const struct audio_port_config& config) {
    CHKP_AND_RET(dev_, -1);
    return dev_->set_audio_port_config(dev_, &config);
}

uint32_t AudioServiceBinder::Stream_get_sample_rate(struct audio_stream* stream_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_hw, -1);
    return stream_hw->get_sample_rate(stream_hw);
}

size_t AudioServiceBinder::Stream_get_buffer_size(struct audio_stream* stream_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_hw, -1);
    return stream_hw->get_buffer_size(stream_hw);
}

uint32_t AudioServiceBinder::Stream_get_channels(struct audio_stream* stream_hw) {
    return (uint32_t) stream_hw->get_channels(stream_hw);
}

uint32_t AudioServiceBinder::Stream_get_format(struct audio_stream* stream_hw) {;
    return (uint32_t) stream_hw->get_format(stream_hw);
}

uint32_t AudioServiceBinder::Stream_standby(struct audio_stream* stream_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_hw, -1);
    return (uint32_t) stream_hw->standby(stream_hw);
}

uint32_t AudioServiceBinder::Stream_get_device(struct audio_stream* stream_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_hw, -1);
    return (uint32_t) stream_hw->get_device(stream_hw);
}

int AudioServiceBinder::Stream_set_parameters(struct audio_stream* stream_hw, const char* kv_pairs) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_hw, -1);
    return stream_hw->set_parameters(stream_hw, kv_pairs);
}

char* AudioServiceBinder::Stream_get_parameters(struct audio_stream* stream_hw, const char* keys) {
    CHKP_AND_RET(dev_, nullptr);
    CHKP_AND_RET(stream_hw, nullptr);
    return stream_hw->get_parameters(stream_hw, keys);
}

uint32_t AudioServiceBinder::StreamOut_get_latency(struct audio_stream_out* stream_out_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);
    return stream_out_hw->get_latency(stream_out_hw);
}

int AudioServiceBinder::StreamOut_set_volume(struct audio_stream_out* stream_out_hw, float left, float right) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);
    return stream_out_hw->set_volume(stream_out_hw, left, right);
}

ssize_t AudioServiceBinder::StreamOut_write(audio_stream_out_info_t* stream_out_info, size_t bytes) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_info, -1);

    {
        std::lock_guard<std::mutex> lock(stream_out_info->stream_mutex);

        if (stream_out_info->shm == nullptr) {
            const char* name = stream_out_info->name;
            std::cout << PROCESS_NAME_LOG << " Shared memory to " << OUTPUT_STREAM_LABEL << " " << name << " was not previously allocated on service. Allocating." << std::endl;
            if (setShmAndFdForStreamOutInfo(name, stream_out_info) == -1) {
                return -1;
            }
        }
    }

    struct audio_stream_out* stream_out_hw = stream_out_info->stream_out_hw;
    CHKP_AND_RET(stream_out_hw, -1);

    {
        std::lock_guard<std::mutex> lock(stream_out_info->stream_mutex);
        CHKP_AND_RET(stream_out_info->shm, -1);
        return stream_out_hw->write(stream_out_hw, stream_out_info->shm, bytes);
    }
}

int AudioServiceBinder::StreamOut_get_render_position(struct audio_stream_out* stream_out_hw, uint32_t& dsp_frames) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);

    dsp_frames = 0;
    return stream_out_hw->get_render_position(stream_out_hw, &dsp_frames);
}

int AudioServiceBinder::StreamOut_get_next_write_timestamp(struct audio_stream_out* stream_out_hw, int64_t& timestamp) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);

    timestamp = 0;
    return stream_out_hw->get_next_write_timestamp(stream_out_hw, &timestamp);
}

int AudioServiceBinder::StreamOut_pause(struct audio_stream_out* stream_out_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);
    return stream_out_hw->pause(stream_out_hw);
}

int AudioServiceBinder::StreamOut_resume(struct audio_stream_out* stream_out_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);
    return stream_out_hw->resume(stream_out_hw);
}

int AudioServiceBinder::StreamOut_flush(struct audio_stream_out* stream_out_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);
    return stream_out_hw->flush(stream_out_hw);
}

int AudioServiceBinder::StreamOut_get_presentation_position(struct audio_stream_out* stream_out_hw,
                                                        uint64_t& frames,
                                                        struct timespec& timestamp) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_out_hw, -1);

    frames = 0;
    return stream_out_hw->get_presentation_position(stream_out_hw, &frames, &timestamp);
}

int AudioServiceBinder::StreamIn_set_gain(struct audio_stream_in* stream_in_hw, float gain) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_in_hw, -1);
    return stream_in_hw->set_gain(stream_in_hw, gain);
}

int AudioServiceBinder::StreamIn_read(audio_stream_in_info_t* stream_in_info, size_t bytes) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_in_info, -1);

    {
        std::lock_guard<std::mutex> lock(stream_in_info->stream_mutex);

        if (stream_in_info->shm == nullptr) {
            const char* name = stream_in_info->name;
            std::cout << PROCESS_NAME_LOG << " Shared memory to " << INPUT_STREAM_LABEL << " " << name << " was not previously allocated on service. Allocating." << std::endl;
            if (setShmAndFdForStreamInInfo(name, stream_in_info) == -1) {
                return -1;
            }
        }
    }

    struct audio_stream_in* stream_in_hw = stream_in_info->stream_in_hw;
    CHKP_AND_RET(stream_in_hw, -1);

    {
        std::lock_guard<std::mutex> lock(stream_in_info->stream_mutex);
        CHKP_AND_RET(stream_in_info->shm, -1);
        return stream_in_hw->read(stream_in_hw, stream_in_info->shm, std::min(bytes, (size_t) KSHAREDBUFFERSIZE));
    }
}

uint32_t AudioServiceBinder::StreamIn_get_input_frames_lost(struct audio_stream_in* stream_in_hw) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_in_hw, -1);
    return stream_in_hw->get_input_frames_lost(stream_in_hw);
}

int AudioServiceBinder::StreamIn_get_capture_position(struct audio_stream_in* stream_in_hw, int64_t& frames, int64_t& time) {
    CHKP_AND_RET(dev_, -1);
    CHKP_AND_RET(stream_in_hw, -1);

    frames = time = 0;
    return stream_in_hw->get_capture_position(stream_in_hw, &frames, &time);
}

int AudioServiceBinder::Service_ping(int& status_32) {
    status_32 = 0;
    return 0;
}

int AudioServiceBinder::Effect_set_parameters(aml_audio_effect_type_e type,
                                        uint32_t cmdSize,
                                        void* pCmdData,
                                        uint32_t replySize,
                                        uint32_t& pReplyData) {
    if (!dev_ || !effect_) return -1;

    pReplyData = 0;
    return effect_->set_parameters(type, cmdSize, pCmdData, &replySize, &pReplyData);
}

int AudioServiceBinder::Effect_get_parameters(aml_audio_effect_type_e type,
                            uint32_t cmdSize,
                            void* pCmdData,
                            uint32_t& replySize,
                            void* pReplyData) {
    if (!dev_ || !effect_) return -1;

    return effect_->get_parameters(type, cmdSize, pCmdData, &replySize, pReplyData);
}

void AudioServiceBinder::stream_gc_(const std::unordered_map<std::string, stream_data_t>& streamsInfo) {
    for (std::unordered_map<std::string, stream_data_t>::const_iterator streamsInfoItr = streamsInfo.begin(); streamsInfoItr != streamsInfo.end(); ++streamsInfoItr) {
        const std::string streamName = streamsInfoItr->first;
        const char* streamNameCStr = streamName.c_str();

        stream_data_t streamData = streamsInfoItr->second;
        audio_stream_direction streamDirection = streamData.first;
        void* streamInfo = streamData.second;

        if (streamDirection == AUDIO_STREAM_OUT) {
            audio_stream_out_info_t* stream_out_info = static_cast<audio_stream_out_info_t*>(streamInfo);
            if (stream_out_info != nullptr) {
                streamout_gc_(stream_out_info->stream_mutex, streamNameCStr, stream_out_info->shm, stream_out_info->fd, stream_out_info->stream_out_hw);
                delete stream_out_info;
                stream_out_info = nullptr;
            }
        } else {
            audio_stream_in_info_t* stream_in_info = static_cast<audio_stream_in_info_t*>(streamInfo);
            if (stream_in_info != nullptr) {
                streamin_gc_(stream_in_info->stream_mutex, streamNameCStr, stream_in_info->shm, stream_in_info->fd, stream_in_info->stream_in_hw);
                delete stream_in_info;
                stream_in_info = nullptr;
            }
        }
    }
}

void AudioServiceBinder::streamout_gc_(std::mutex& stream_mutex, const char* name, void* shm, int fd, audio_stream_out* stream_out_hw) {
    {
        std::lock_guard<std::mutex> lock(stream_mutex);
        posixUnmapDataCloseFileAndUnlinkName(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, name, shm, KSHAREDBUFFERSIZE, fd);
    }

    if (dev_ && stream_out_hw) {
        std::cout << PROCESS_NAME_LOG << " close " << OUTPUT_STREAM_LABEL << " " << name << std::endl;
        dev_->close_output_stream(dev_, stream_out_hw);
    }
}

void AudioServiceBinder::streamin_gc_(std::mutex& stream_mutex, const char* name, void* shm, int fd, audio_stream_in* stream_in_hw) {
    {
        std::lock_guard<std::mutex> lock(stream_mutex);
        posixUnmapDataCloseFileAndUnlinkName(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, name, shm, KSHAREDBUFFERSIZE, fd);
    }

    if (dev_ && stream_in_hw) {
        std::cout << PROCESS_NAME_LOG << " close " << INPUT_STREAM_LABEL << " " << name << std::endl;
        dev_->close_input_stream(dev_, stream_in_hw);
    }
}

int AudioServiceBinder::updateStreamOutInfo(const char* name, struct audio_stream_out* stream, audio_stream_out_info_t* stream_out_info) {
    strcpy(stream_out_info->name, name);
    stream_out_info->stream_out_hw = stream;
    {
        std::lock_guard<std::mutex> lock(stream_out_info->stream_mutex);
        return setShmAndFdForStreamOutInfo(name, stream_out_info);
    }
}

int AudioServiceBinder::updateStreamInInfo(const char* name, struct audio_stream_in* stream, audio_stream_in_info_t* stream_in_info) {
    strcpy(stream_in_info->name, name);
    stream_in_info->stream_in_hw = stream;
    {
        std::lock_guard<std::mutex> lock(stream_in_info->stream_mutex);
        return setShmAndFdForStreamInInfo(name, stream_in_info);
    }
}

int AudioServiceBinder::setShmAndFdForStreamOutInfo(const char* name, audio_stream_out_info_t* stream_out_info) {
    umask(STREAM_OBJECT_UMASK);

    int fd; void* streamoutShm;
    fd = posixOpenFileSetDataSizeAndMapData(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, name, O_CREAT | O_RDWR, S_IRWXU | S_IRWXG | S_IRWXO, KSHAREDBUFFERSIZE,
                                        streamoutShm, PROT_READ | PROT_WRITE, MAP_SHARED);
    if (fd == -1) { return -1; }
    stream_out_info->fd = fd;
    stream_out_info->shm = streamoutShm;

    return 0;
}

int AudioServiceBinder::setShmAndFdForStreamInInfo(const char* name, audio_stream_in_info_t* stream_in_info) {
    umask(STREAM_OBJECT_UMASK);

    int fd; void* streaminShm;
    fd = posixOpenFileSetDataSizeAndMapData(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, name, O_CREAT | O_RDWR, S_IRWXU | S_IRWXG | S_IRWXO, KSHAREDBUFFERSIZE,
                                        streaminShm, PROT_READ | PROT_WRITE, MAP_SHARED);
    if (fd == -1) { return -1; }
    stream_in_info->fd = fd;
    stream_in_info->shm = streaminShm;

    return 0;
}

void AudioServiceBinder::update_gc_stream_map(::android::sp<::android::IBinder> audioClientBinder,
                                            int client_id,
                                            const std::string& stream_id,
                                            audio_stream_direction streamType,
                                            void* streamInfo) {
    std::lock_guard<std::mutex> lock(gc_map_mutex_);

    std::pair<std::string, stream_data_t> streamDataEntry(stream_id, stream_data_t(streamType, streamInfo));

    std::unordered_map<int, gc_stream_map_t>::iterator it = gc_stream_map_.find(client_id);
    if (it == gc_stream_map_.end()) {
        ::android::sp<ServiceDeathRecipient> serviceDeathRecipient = new ServiceDeathRecipient(this, client_id);
        audioClientBinder->linkToDeath(serviceDeathRecipient);

        std::unordered_map<std::string, stream_data_t> streamsInfo;
        streamsInfo.insert(streamDataEntry);

        gc_stream_map_.insert(std::pair<int, gc_stream_map_t>(client_id, gc_stream_map_t(serviceDeathRecipient, streamsInfo)));
    } else {
        // service death recipient registered to client_id
        it->second.second.insert(streamDataEntry);
    }
}

void AudioServiceBinder::remove_stream_info_from_gc_stream_map(int clientPid, const std::string& name) {
    std::lock_guard<std::mutex> lock_gc(gc_map_mutex_);

    std::unordered_map<int, gc_stream_map_t>::iterator it = gc_stream_map_.find(clientPid);
    if (it == gc_stream_map_.end()) return;

    it->second.second.erase(name);
}

void AudioServiceBinder::readAudioConfigFromParcel(struct audio_config& config, const ::android::Parcel& parcel) {
    uint32_t sample_rate_channel_mask_frame_count[3];
    parcel.read(sample_rate_channel_mask_frame_count, sizeof(sample_rate_channel_mask_frame_count));
    config.sample_rate = sample_rate_channel_mask_frame_count[0];
    config.channel_mask = (audio_channel_mask_t) sample_rate_channel_mask_frame_count[1];
    config.frame_count = sample_rate_channel_mask_frame_count[2];
    config.format = (audio_format_t) parcel.readInt32();
}

void AudioServiceBinder::readAudioPortConfigFromParcel(struct audio_port_config& config, const ::android::Parcel& parcel) {
    config.id = parcel.readInt32();
    config.role = (audio_port_role_t) parcel.readInt32();

    audio_port_type_t type = (audio_port_type_t) parcel.readInt32();
    config.type = type;

    config.config_mask = parcel.readUint32();
    config.sample_rate = parcel.readUint32();
    config.channel_mask = parcel.readUint32();
    config.format = (audio_format_t) parcel.readInt32();

    struct audio_gain_config* gain = &config.gain;
    gain->index = parcel.readInt32();
    gain->mode = (audio_gain_mode_t) parcel.readUint32();
    gain->channel_mask = (audio_channel_mask_t) parcel.readInt32();

    parcel.read(gain->values, sizeof(gain->values));

    gain->ramp_duration_ms = parcel.readUint32();

    if (type == AUDIO_PORT_TYPE_DEVICE) {
        struct audio_port_config_device_ext* device = &config.ext.device;
        device->hw_module = (audio_module_handle_t) parcel.readInt32();
        device->type = (audio_devices_t) parcel.readUint32();
        strncpy(device->address, parcel.readCString(), AUDIO_DEVICE_MAX_ADDRESS_LEN);
    } else if (type == AUDIO_PORT_TYPE_MIX) {
        struct audio_port_config_mix_ext* mix = &config.ext.mix;
        mix->hw_module = (audio_module_handle_t) parcel.readInt32();
        mix->handle = (audio_io_handle_t) parcel.readInt32();
        mix->usecase.stream = (audio_stream_type_t) parcel.readInt32();
    } else if (type == AUDIO_PORT_TYPE_SESSION) {
        config.ext.session.session = (audio_session_t) parcel.readInt32();
    }
}

void AudioServiceBinder::readAudioPortConfigsFromParcel(unsigned int numConfigs, struct audio_port_config* configs, const ::android::Parcel& parcel) {
    struct audio_port_config* config = configs;
    for (unsigned int i = 0; i < numConfigs; i++, config++) { readAudioPortConfigFromParcel(*config, parcel); }
}

::android::status_t AudioServiceBinder::onTransact(uint32_t code, const ::android::Parcel& data, ::android::Parcel* reply, uint32_t flags) {
    switch (code) {
        case CMD_AS_DCC: {
            int ret = Device_common_close();
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DIC: {
            int ret = Device_init_check();
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DSVV: {
            int ret = Device_set_voice_volume(data.readFloat());
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DSMV: {
            int ret = Device_set_master_volume(data.readFloat());
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DGMV: {
            float masterVolume;
            int ret = Device_get_master_volume(masterVolume);
            reply->writeInt32(ret);
            reply->writeFloat(masterVolume);
            break;
        }
        case CMD_AS_DSM: {
            audio_mode_t mode = (audio_mode_t) data.readInt32();
            int ret = Device_set_mode(mode);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DSMicM: {
            bool state = data.readInt32();
            int ret = Device_set_mic_mute(state);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DGMicM: {
            bool state;
            int ret = Device_get_mic_mute(state);
            reply->writeInt32(ret);

            int stateInt = state;
            reply->writeInt32(stateInt);
            break;
        }
        case CMD_AS_DSP: {
            const char* kv_pairs = data.readCString();
            int ret = Device_set_parameters(kv_pairs);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DGP: {
            const char* keys = data.readCString();
            char* params = Device_get_parameters(keys);
            reply->writeCString(params);
            break;
        }
        case CMD_AS_DGIBS: {
            struct audio_config config; readAudioConfigFromParcel(config, data);
            int ret = Device_get_input_buffer_size(config);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DOOS: {
            ::android::sp<::android::IBinder> audioClientBinder = data.readStrongBinder();
            int seq = data.readInt32();
            audio_io_handle_t handle = (audio_io_handle_t) data.readInt32();
            audio_devices_t devices = (audio_devices_t) data.readUint32();
            audio_output_flags_t flags = (audio_output_flags_t) data.readInt32();
            struct audio_config config; readAudioConfigFromParcel(config, data);
            const char* address = data.readCString();

            int clientId;
            struct audio_stream* stream_hw = nullptr;
            struct audio_stream_out_info* stream_out_info = nullptr;

            int ret = Device_open_output_stream(audioClientBinder, seq, handle, devices, flags, config, address, clientId, stream_hw, stream_out_info);

            if (ret && stream_out_info != nullptr) {
                delete stream_out_info;
                stream_out_info = nullptr;
            }

            reply->writeInt32(ret);
            if (ret == 0) {
                reply->writeInt32(clientId);
                reply->write(&stream_hw, sizeof(stream_hw));
                reply->write(&stream_out_info, sizeof(stream_out_info));
            }

            break;
        }
        case CMD_AS_DCOS: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            Device_close_output_stream(stream_out_info);
            break;
        }
        case CMD_AS_DOIS: {
            ::android::sp<::android::IBinder> audioClientBinder = data.readStrongBinder();
            int seq = data.readInt32();
            audio_io_handle_t handle = (audio_io_handle_t) data.readInt32();
            audio_devices_t devices = (audio_devices_t) data.readUint32();
            struct audio_config config; readAudioConfigFromParcel(config, data);
            audio_input_flags_t flags = (audio_input_flags_t) data.readInt32();
            const char* address = data.readCString();
            audio_source_t source = (audio_source_t) data.readInt32();

            int clientId;
            struct audio_stream* stream_hw = nullptr;
            struct audio_stream_in_info* stream_in_info = nullptr;

            int ret = Device_open_input_stream(audioClientBinder, seq, handle, devices, config, flags, address, source, clientId, stream_hw, stream_in_info);

            if (ret && stream_in_info != nullptr) {
                delete stream_in_info;
                stream_in_info = nullptr;
            }

            reply->writeInt32(ret);
            if (ret == 0) {
                reply->writeInt32(clientId);
                reply->write(&stream_hw, sizeof(stream_hw));
                reply->write(&stream_in_info, sizeof(stream_in_info));
            }
            break;
        }
        case CMD_AS_DCIS: {
            audio_stream_in_info_t* stream_in_info; data.read(&stream_in_info, sizeof(stream_in_info));
            Device_close_input_stream(stream_in_info);
            break;
        }
        case CMD_AS_DD: {
            std::string deviceDump;
            int ret = Device_dump(deviceDump);
            reply->writeInt32(ret);
            reply->writeCString(deviceDump.c_str());
            break;
        }
        case CMD_AS_DSMasterM: {
            bool mute = data.readInt32();
            int ret = Device_set_master_mute(mute);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DGMasterM: {
            bool mute;
            int ret = Device_get_master_mute(mute);
            reply->writeInt32(ret);

            int muteInt = mute;
            reply->writeInt32(muteInt);
            break;
        }
        case CMD_AS_DCAP: {
            unsigned int dcap_num_sources, dcap_num_sinks;
            dcap_num_sources = data.readUint32(), dcap_num_sinks = data.readUint32();
            struct audio_port_config* dcapSources = new audio_port_config[dcap_num_sources], *dcapSinks = new audio_port_config[dcap_num_sinks];
            readAudioPortConfigsFromParcel(dcap_num_sources, dcapSources, data);
            readAudioPortConfigsFromParcel(dcap_num_sinks, dcapSinks, data);

            audio_patch_handle_t handle;
            int ret = Device_create_audio_patch(dcap_num_sources, dcapSources, dcap_num_sinks, dcapSinks, handle);
            delete [] dcapSources; delete [] dcapSinks;
            reply->writeInt32(ret);
            reply->writeInt32(handle);
            break;
        }
        case CMD_AS_DRAP: {
            audio_patch_handle_t handle;
            data.read(&handle, sizeof(audio_patch_handle_t));
            int ret = Device_release_audio_patch(handle);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_DSAPC: {
            struct audio_port_config config; readAudioPortConfigFromParcel(config, data);
            int ret = Device_set_audio_port_config(config);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SGSR: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            uint32_t ret = Stream_get_sample_rate(stream_hw);
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SGBS: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            int ret = Stream_get_buffer_size(stream_hw);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SGC: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            uint32_t ret = Stream_get_channels(stream_hw);

            // ret is channel, not return code
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SGF: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            uint32_t ret = Stream_get_format(stream_hw);

            // ret is format, not return code
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SS: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            uint32_t ret = Stream_standby(stream_hw);
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SGD: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            uint32_t ret = Stream_get_device(stream_hw);
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SSP: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            const char* kv_pairs = data.readCString();
            int ret = Stream_set_parameters(stream_hw, kv_pairs);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SGP: {
            struct audio_stream* stream_hw; data.read(&stream_hw, sizeof(stream_hw));
            const char* keys = data.readCString();
            char* params = Stream_get_parameters(stream_hw, keys);
            reply->writeCString(params);
            break;
        }
        case CMD_AS_SO_GL: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            uint32_t ret = StreamOut_get_latency(stream_out_info->stream_out_hw);
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SO_SV: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            float left = data.readFloat();
            float right = data.readFloat();
            int ret = StreamOut_set_volume(stream_out_info->stream_out_hw, left, right);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SO_W: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            size_t bytes; data.read(&bytes, sizeof(bytes));
            int ret = StreamOut_write(stream_out_info, bytes);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SO_GRP: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            uint32_t dsp_frames;
            int ret = StreamOut_get_render_position(stream_out_info->stream_out_hw, dsp_frames);
            reply->writeInt32(ret);
            reply->writeUint32(dsp_frames);
            break;
        }
        case CMD_AS_SO_GNWT: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            int64_t timestamp;
            int ret = StreamOut_get_next_write_timestamp(stream_out_info->stream_out_hw, timestamp);
            reply->writeInt32(ret);
            reply->writeInt64(timestamp);
            break;
        }
        case CMD_AS_SO_P: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            int ret = StreamOut_pause(stream_out_info->stream_out_hw);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SO_R: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            int ret = StreamOut_resume(stream_out_info->stream_out_hw);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SO_F: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            int ret = StreamOut_flush(stream_out_info->stream_out_hw);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SO_GPP: {
            audio_stream_out_info_t* stream_out_info; data.read(&stream_out_info, sizeof(stream_out_info));
            uint64_t frames; struct timespec timestamp;
            int ret = StreamOut_get_presentation_position(stream_out_info->stream_out_hw, frames, timestamp);
            reply->writeInt32(ret);
            reply->writeUint64(frames);
            reply->writeInt64((int64_t) timestamp.tv_sec);
            reply->write(&timestamp.tv_nsec, sizeof(timestamp.tv_nsec));
            break;
        }
        case CMD_AS_SI_SG: {
            audio_stream_in_info_t* stream_in_info; data.read(&stream_in_info, sizeof(stream_in_info));
            float gain = data.readFloat();
            int ret = StreamIn_set_gain(stream_in_info->stream_in_hw, gain);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SI_R: {
            audio_stream_in_info_t* stream_in_info; data.read(&stream_in_info, sizeof(stream_in_info));
            size_t bytes; data.read(&bytes, sizeof(bytes));
            int ret = StreamIn_read(stream_in_info, bytes);
            reply->writeInt32(ret);
            break;
        }
        case CMD_AS_SI_GIFL: {
            audio_stream_in_info_t* stream_in_info; data.read(&stream_in_info, sizeof(stream_in_info));
            uint32_t ret = StreamIn_get_input_frames_lost(stream_in_info->stream_in_hw);
            reply->writeUint32(ret);
            break;
        }
        case CMD_AS_SI_GCP: {
            struct audio_stream_in_info* stream_in_info; data.read(&stream_in_info, sizeof(stream_in_info));
            int64_t frames, time;
            int ret = StreamIn_get_capture_position(stream_in_info->stream_in_hw, frames, time);
            reply->writeInt32(ret);
            reply->writeInt64(frames);
            reply->writeInt64(time);
            break;
        }
        case CMD_AS_SP: {
            int status_32 = -999;
            int ret = Service_ping(status_32);
            reply->writeInt32(ret);
            reply->writeCString(std::to_string(status_32).c_str());
            break;
        }
        case CMD_AS_ESP: {
            aml_audio_effect_type_e type = (aml_audio_effect_type_e) data.readInt32();
            uint32_t cmdSize = data.readUint32();
            void* pCmdData = calloc(cmdSize, 1);
            data.read(pCmdData, cmdSize);
            uint32_t replySize = data.readUint32();

            uint32_t pReplyData;
            int ret = Effect_set_parameters(type, cmdSize, pCmdData, replySize, pReplyData);
            reply->writeUint32(pReplyData);
            reply->writeInt32(ret);
            free(pCmdData);
            break;
        }
        case CMD_AS_EGP: {
            aml_audio_effect_type_e type = (aml_audio_effect_type_e) data.readInt32();
            uint32_t cmdSize = data.readUint32();
            void* pCmdData = calloc(cmdSize, 1);
            data.read(pCmdData, cmdSize);
            uint32_t replySize = data.readUint32();

            void* pReplyData = malloc(replySize);
            int ret = Effect_get_parameters(type, cmdSize, pCmdData, replySize, pReplyData);
            reply->writeInt32(ret);

            if (!ret) {
                reply->writeUint32(replySize);
                reply->write(pReplyData, replySize);
            }

            free(pReplyData);
            free(pCmdData);
            pReplyData = nullptr;
            break;
        }
        default:
            return ::android::BBinder::onTransact(code, data, reply, flags);
    }

    return (0);
}
