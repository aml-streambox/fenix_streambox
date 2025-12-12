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

#include <binder/ProcessState.h>

#include "audio_client_binder.h"
#include "client_death_recipient.h"

#define CHK_SERVICE_AND_RET(r) \
    do { \
        if (mAudioServiceBinder == nullptr) { \
            std::cout << PROCESS_NAME_LOG << " mAudioServiceBinder is NULL." << std::endl; \
            return (r); \
        } \
    } while (0)

#define CHK_SERVICE() \
    do { \
        if (mAudioServiceBinder == nullptr) { \
            std::cout << PROCESS_NAME_LOG << " mAudioServiceBinder is NULL." << std::endl; \
            return; \
        } \
    } while (0)

#define CHK_TRANSACT_RET_AND_RET(tr, l, r) \
    do { \
        if ((tr) != 0) { \
            if ((tr) == BINDER_EXCEPTION) { std::cout << PROCESS_NAME_LOG << " Service exception." << std::endl; on_service_exception(); } \
            std::cout << PROCESS_NAME_LOG << " Error with transact " << (l) << ". transactRet = " << (tr) << "." << std::endl; \
            return (r); \
        } \
    } while (0)

#define CHK_TRANSACT_RET(tr, l) \
    do { \
        if ((tr) != 0) { \
            if ((tr) == BINDER_EXCEPTION) { std::cout << PROCESS_NAME_LOG << " Service exception." << std::endl; on_service_exception(); } \
            std::cout << PROCESS_NAME_LOG << " Error with transact " << (l) << ". transactRet = " << (tr) << "." << std::endl; \
            return; \
        } \
    } while (0)

namespace acb {
    template<typename T> void writeDataToParcel(const T& data, ::android::Parcel& parcel);
    template<> void writeDataToParcel<int>(const int& data, ::android::Parcel& parcel) { parcel.writeInt32(data); }
    template<> void writeDataToParcel<float>(const float& data, ::android::Parcel& parcel) { parcel.writeFloat(data); }
    template<> void writeDataToParcel<char*>(char* const& data, ::android::Parcel& parcel) { parcel.writeCString(data); }
    template<> void writeDataToParcel<const char*>(const char* const& data, ::android::Parcel& parcel) { parcel.writeCString(data); }
    template<> void writeDataToParcel<void*>(void* const& data, ::android::Parcel& parcel) { parcel.write(&data, sizeof(data)); }

    template<typename R> R readDataFromParcel(const ::android::Parcel& parcel);
    template<> uint32_t readDataFromParcel<uint32_t>(const ::android::Parcel& parcel) { return parcel.readUint32(); }
    template<> int readDataFromParcel<int>(const ::android::Parcel& parcel) { return parcel.readInt32(); }
    template<> int64_t readDataFromParcel<int64_t>(const ::android::Parcel& parcel){ return parcel.readInt64(); }
    template<> float readDataFromParcel<float>(const ::android::Parcel& parcel) { return parcel.readFloat(); }
    template<> const char* readDataFromParcel<const char*>(const ::android::Parcel& parcel) { return parcel.readCString(); }
}

std::mutex AudioClientBinder::stream_in_clients_mutex_;
std::mutex AudioClientBinder::stream_out_clients_mutex_;
std::mutex AudioClientBinder::on_service_exception_mutex_;

AudioClientBinder::AudioClientBinder() {
    ::android::sp<::android::ProcessState> proc(::android::ProcessState::self());
    proc->startThreadPool();
    ::android::sp<::android::IServiceManager> serviceManager = ::android::defaultServiceManager();

    while (true) {
        SetAudioPermissions(PROCESS_NAME_LOG, BINDERFSPATH);
        SetAudioPermissions(PROCESS_NAME_LOG, POSIXSHMPATH);

        std::cout << PROCESS_NAME_LOG << " Getting reference to binder of audio server." << std::endl;
        mAudioServiceBinder = serviceManager->getService(::android::String16(NAME_OF_SERVICE));
        if (mAudioServiceBinder != 0) {
            std::cout << PROCESS_NAME_LOG << " Got reference to binder of audio server." << std::endl;
            mService = true;

            clientDeathRecipient = new ClientDeathRecipient(this);
            mAudioServiceBinder->linkToDeath(clientDeathRecipient);

            break;
        }

        std::cout << PROCESS_NAME_LOG << " Could not get reference to service " << NAME_OF_SERVICE << "." << std::endl;

        if (++numTries == MAX_NUM_TRIES_TO_GET_SERVICE) {
            break;
        }
    }
}

void AudioClientBinder::setspInstance(::android::sp<AudioClientBinder> spInstance) { spInstance_ = spInstance; }

void AudioClientBinder::gc() {
    {
        std::lock_guard<std::mutex> lock_out(stream_out_clients_mutex_);
        cleanStreamoutClients();
    }

    {
        std::lock_guard<std::mutex> lock_in(stream_in_clients_mutex_);
        cleanStreaminClients();
    }

    if (clientDeathRecipient != nullptr) clientDeathRecipient.clear();
}

bool AudioClientBinder::gotService() { return mService; }

void AudioClientBinder::on_service_exception() {
    std::lock_guard<std::mutex> lock(on_service_exception_mutex_);

    if (spInstance_ != nullptr) {
        spInstance_->gc();
        spInstance_.clear();
    }
}

int AudioClientBinder::Device_common_close() {
    return transactNoDataRetNum<int>(CMD_AS_DCC, "for device common close");
}

int AudioClientBinder::Device_init_check() {
    return transactNoDataRetNum<int>(CMD_AS_DIC, "for device init check");
}

int AudioClientBinder::Device_set_voice_volume(float volume) {
    return transactDataRetNum<float, int>(volume, CMD_AS_DSVV, "data for device set voice volume");
}

int AudioClientBinder::Device_set_master_volume(float volume) {
    return transactDataRetNum<float, int>(volume, CMD_AS_DSMV, "data for device set master volume");
}

int AudioClientBinder::Device_get_master_volume(float& masterVolume) {
    return transactNoDataRetNumGetRef<int, float>(masterVolume, CMD_AS_DGMV, "for device get master volume");
}

int AudioClientBinder::Device_set_mode(audio_mode_t mode) {
    return transactDataRetNum<int, int>(mode, CMD_AS_DSM, "data for device set mode");
}

int AudioClientBinder::Device_set_mic_mute(bool state) {
    int stateInt = state;
    return transactDataRetNum<int, int>(stateInt, CMD_AS_DSMicM, "data for device set mic mute");
}

int AudioClientBinder::Device_get_mic_mute(bool& state) {
    int stateInt;
    int ret = transactNoDataRetNumGetRef<int, int>(stateInt, CMD_AS_DGMicM, "for device get mic mute");
    if (ret == 0) { state = stateInt; }
    return ret;
}

int AudioClientBinder::Device_set_parameters(const char* kv_pairs) {
    return transactDataRetNum<const char*, int>(kv_pairs, CMD_AS_DSP, "data for device set parameters");
}

char* AudioClientBinder::Device_get_parameters(const char* keys) {
    const char* params;
    transactDataGetRef<const char*, const char*>(keys, params, CMD_AS_DGP, "data for device get parameters");

    if (!params) { return nullptr; }

    int lenParams = strlen(params);

    char* p = static_cast<char*>(malloc(lenParams + 1));
    if (p) {
        strncpy(p, params, lenParams + 1);
    }
    return p;
}

size_t AudioClientBinder::Device_get_input_buffer_size(const struct audio_config* config) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    writeAudioConfigToParcel(config, send);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_DGIBS, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for device get input buffer size", transactRet);

    return reply.readInt32();
}

int AudioClientBinder::Device_open_output_stream(audio_io_handle_t handle,
                                            audio_devices_t devices,
                                            audio_output_flags_t flags,
                                            struct audio_config* config,
                                            audio_stream_out_client_t*& stream_out_client,
                                            const char* address) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    stream_out_client = new audio_stream_out_client_t;
    if (!stream_out_client) return -ENOMEM;

    stream_out_client->shm = nullptr;

    send.writeStrongBinder(::android::sp<AudioClientBinder>(this));

    int seq = new_stream_name(stream_out_client->name, sizeof(stream_out_client->name));
    send.writeInt32(seq);

    int handleTransact = handle;
    send.writeInt32(handleTransact);

    uint32_t devicesTransact = devices;
    send.writeUint32(devicesTransact);

    int flagsTransact = flags;
    send.writeInt32(flagsTransact);

    writeAudioConfigToParcel(config, send);

    const char* addressInfo = address ? address : "";
    send.writeCString(addressInfo);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_DOOS, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for device open output stream", transactRet);

    int ret = reply.readInt32();
    if (ret == 0) {
        if (updateStreamOutClient(reply, stream_out_client) == -1) {
            return -1;
        }
        {
            std::lock_guard<std::mutex> lock(stream_out_clients_mutex_);
            streamoutClients.insert(std::pair<std::string, audio_stream_out_client_t*>(std::string(stream_out_client->name), stream_out_client));
        }
    }

    return ret;
}

void AudioClientBinder::Device_close_output_stream(struct audio_stream_out* stream_out) {
    // If streamoutClients is empty, then gc has been executed.
    // gc is executed if service dies if client is on and has opened stream.
    // If gc has been executed, then the memory for stream out client has been freed.
    {
        std::lock_guard<std::mutex> lock(stream_out_clients_mutex_);
        if (streamoutClients.empty()) return;
    }

    audio_stream_out_client_t* stream_out_client = audio_stream_out_to_client(stream_out);

    const char* name = stream_out_client->name;
    {
        std::lock_guard<std::mutex> lock(stream_out_client->stream_mutex);
        posixCloseFile(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, name, stream_out_client->fd);
        stream_out_client->shm = nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(stream_out_clients_mutex_);
        streamoutClients.erase(std::string(name));
    }

    transactData<void*>(stream_out_client->stream_out_info, CMD_AS_DCOS, "data for device close output stream");

    if (stream_out_client != nullptr) {
        delete stream_out_client;
        stream_out_client = nullptr;
    }
}

int AudioClientBinder::Device_open_input_stream(audio_io_handle_t handle,
                                            audio_devices_t devices,
                                            struct audio_config* config,
                                            audio_stream_in_client_t*& stream_in_client,
                                            audio_input_flags_t flags,
                                            const char* address,
                                            audio_source_t source) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    stream_in_client = new audio_stream_in_client_t;
    if (!stream_in_client) return -ENOMEM;

    stream_in_client->shm = nullptr;

    send.writeStrongBinder(::android::sp<AudioClientBinder>(this));

    int seq = new_stream_name(stream_in_client->name, sizeof(stream_in_client->name));
    send.writeInt32(seq);

    int handleTransact = handle;
    send.writeInt32(handleTransact);

    uint32_t devicesTransact = devices;
    send.writeUint32(devicesTransact);

    writeAudioConfigToParcel(config, send);

    int flagsTransact = flags;
    send.writeInt32(flagsTransact);

    const char* addressInfo = address ? address : "";
    send.writeCString(addressInfo);

    send.writeInt32(source);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_DOIS, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for device open input stream", transactRet);

    int ret = reply.readInt32();
    if (ret == 0) {
        if (updateStreamInClient(reply, stream_in_client) == -1) {
            return -1;
        }
        {
            std::lock_guard<std::mutex> lock(stream_in_clients_mutex_);
            streaminClients.insert(std::pair<std::string, audio_stream_in_client_t*>(std::string(stream_in_client->name), stream_in_client));
        }
    }

    return ret;
}

void AudioClientBinder::Device_close_input_stream(struct audio_stream_in* stream_in) {
    // If streaminClients is empty, then gc has been executed.
    // gc is executed if service dies if client is on and has opened stream.
    // If gc has been executed, then the memory for stream in client has been freed.
    {
        std::lock_guard<std::mutex> lock(stream_in_clients_mutex_);
        if (streaminClients.empty()) return;
    }

    audio_stream_in_client* stream_in_client = audio_stream_in_to_client(stream_in);

    const char* name = stream_in_client->name;
    {
        std::lock_guard<std::mutex> lock(stream_in_client->stream_mutex);
        posixCloseFile(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, name, stream_in_client->fd);
        stream_in_client->shm = nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(stream_in_clients_mutex_);
        streaminClients.erase(std::string(name));
    }

    transactData<void*>(stream_in_client->stream_in_info, CMD_AS_DCIS, "data for device close input stream");

    if (stream_in_client != nullptr) {
        delete stream_in_client;
        stream_in_client = nullptr;
    }
}

int AudioClientBinder::Device_dump(std::string& deviceDump) {
    const char* deviceDumpCStr;
    int ret = transactNoDataRetNumGetRef<int, const char*>(deviceDumpCStr, CMD_AS_DD, "for device dump");
    if (ret == 0) { deviceDump = std::string(deviceDumpCStr); }
    return ret;
}

int AudioClientBinder::Device_set_master_mute(bool mute) {
    int stateInt = mute;
    return transactDataRetNum<int, int>(stateInt, CMD_AS_DSMasterM, "data for device set master mute");
}

int AudioClientBinder::Device_get_master_mute(bool& mute) {
    int muteInt;
    int ret = transactNoDataRetNumGetRef<int, int>(muteInt, CMD_AS_DGMasterM, "for device get master mute");
    if (ret == 0) { mute = muteInt; }
    return ret;
}

int AudioClientBinder::Device_create_audio_patch(unsigned int num_sources, const struct audio_port_config* sources, unsigned int num_sinks, const struct audio_port_config* sinks, audio_patch_handle_t* handle) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    send.writeUint32(num_sources); send.writeUint32(num_sinks);
    writeAudioPortConfigsToParcel(num_sources, sources, send);
    writeAudioPortConfigsToParcel(num_sinks, sinks, send);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_DCAP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for device create audio patch", transactRet);

    int ret = reply.readInt32();
    *handle = reply.readInt32();
    return ret;
}

int AudioClientBinder::Device_release_audio_patch(audio_patch_handle_t handle) {
    return transactDataRetNum<int, int>(handle, CMD_AS_DRAP, "data for device release audio patch");
}

int AudioClientBinder::Device_set_audio_port_config(const struct audio_port_config* config) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    writeAudioPortConfigToParcel(config, send);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_DSAPC, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for device set audio port config", transactRet);

    return reply.readInt32();
}

uint32_t AudioClientBinder::Stream_get_sample_rate(const struct audio_stream* stream) {
    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    return transactDataRetNum<void*, uint32_t>(stream_hw, CMD_AS_SGSR, "data for stream get sample rate");
}

size_t AudioClientBinder::Stream_get_buffer_size(const struct audio_stream* stream) {
    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    return transactDataRetNum<void*, int>(stream_hw, CMD_AS_SGBS, "data for stream get buffer size");
}

audio_channel_mask_t AudioClientBinder::Stream_get_channels(const struct audio_stream* stream) {
    ::android::Parcel send, reply;

    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    send.write(&stream_hw, sizeof(stream_hw));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SGC, send, &reply);
    if (transactRet != 0) {
        if (transactRet == BINDER_EXCEPTION) { std::cout << PROCESS_NAME_LOG << " Service exception." << std::endl; on_service_exception(); }
        std::cout << PROCESS_NAME_LOG << " Error with transact data for stream get channels. transactRet = " << transactRet << "." << std::endl;
    }

    return (audio_channel_mask_t) reply.readUint32();
}

audio_format_t AudioClientBinder::Stream_get_format(const struct audio_stream* stream) {
    ::android::Parcel send, reply;

    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    send.write(&stream_hw, sizeof(stream_hw));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SGF, send, &reply);
    if (transactRet != 0) {
        if (transactRet == BINDER_EXCEPTION) { std::cout << PROCESS_NAME_LOG << " Service exception." << std::endl; on_service_exception(); }
        std::cout << PROCESS_NAME_LOG << " Error with transact data for stream get format. transactRet = " << transactRet << "." << std::endl;
    }

    return (audio_format_t) reply.readUint32();
}

int AudioClientBinder::Stream_standby(struct audio_stream* stream) {
    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    return transactDataRetNum<void*, uint32_t>(stream_hw, CMD_AS_SS, "data for stream standby");
}

audio_devices_t AudioClientBinder::Stream_get_device(const struct audio_stream* stream) {
    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    return (audio_devices_t) transactDataRetNum<void*, uint32_t>(stream_hw, CMD_AS_SGD, "data for stream get device");
}

int AudioClientBinder::Stream_set_parameters(struct audio_stream* stream, const char* kv_pairs) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    send.write(&stream_hw, sizeof(stream_hw));

    send.writeCString(kv_pairs);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SSP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream set parameters", transactRet);

    return reply.readInt32();
}

char* AudioClientBinder::Stream_get_parameters(const struct audio_stream* stream, const char* keys) {
    CHK_SERVICE_AND_RET(nullptr);

    ::android::Parcel send, reply;

    void* stream_hw = (audio_stream_to_client(stream))->stream_hw;
    send.write(&stream_hw, sizeof(stream_hw));

    send.writeCString(keys);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SGP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream get parameters", nullptr);

    const char* params = reply.readCString();
    if (!params) { return nullptr; }

    int lenParams = strlen(params);

    char* p = static_cast<char*>(malloc(lenParams + 1));
    if (p) {
        strncpy(p, params, lenParams + 1);
    }
    return p;
}

uint32_t AudioClientBinder::StreamOut_get_latency(const struct audio_stream_out* stream) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNum<void*, uint32_t>(stream_out_info, CMD_AS_SO_GL, "data for stream out get latency");
}

int AudioClientBinder::StreamOut_set_volume(struct audio_stream_out* stream, float left, float right) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    send.write(&stream_out_info, sizeof(stream_out_info));

    send.writeFloat(left);
    send.writeFloat(right);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SO_SV, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream out set volume", transactRet);

    return reply.readInt32();
}

ssize_t AudioClientBinder::StreamOut_write(struct audio_stream_out* stream, const void* buffer, size_t bytes) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    audio_stream_out_client_t* stream_out_client = audio_stream_out_to_client(stream);

    {
        std::lock_guard<std::mutex> lock(stream_out_client->stream_mutex);

        if (stream_out_client->shm == nullptr) {
            std::cout << PROCESS_NAME_LOG << " Shared memory to " << OUTPUT_STREAM_LABEL << " " << stream_out_client->name << " was not previously allocated on client. Allocating." << std::endl;
            if (setShmAndFdForStreamOutClient(stream_out_client) == -1) return -1;
        }

        memcpy(stream_out_client->shm, buffer, std::min(bytes, (size_t) KSHAREDBUFFERSIZE));
    }

    send.write(&stream_out_client->stream_out_info, sizeof(stream_out_client->stream_out_info));
    send.write(&bytes, sizeof(bytes));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SO_W, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream out write", transactRet);

    return reply.readInt32();
}

int AudioClientBinder::StreamOut_get_render_position(const struct audio_stream_out* stream, uint32_t* dsp_frames) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNumGetRef<void*, int, uint32_t>(stream_out_info, *dsp_frames, CMD_AS_SO_GRP, "data for stream out get render position");
}

int AudioClientBinder::StreamOut_get_next_write_timestamp(const struct audio_stream_out* stream, int64_t* timestamp) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNumGetRef<void*, int, int64_t>(stream_out_info, *timestamp, CMD_AS_SO_GNWT, "data for stream out get next write timestamp");
}

int AudioClientBinder::StreamOut_pause(struct audio_stream_out* stream) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNum<void*, int>(stream_out_info, CMD_AS_SO_P, "data for stream out pause");
}

int AudioClientBinder::StreamOut_resume(struct audio_stream_out* stream) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNum<void*, int>(stream_out_info, CMD_AS_SO_R, "data for stream out resume");
}

int AudioClientBinder::StreamOut_flush(struct audio_stream_out* stream) {
    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    return transactDataRetNum<void*, int>(stream_out_info, CMD_AS_SO_F, "data for stream out flush");
}

int AudioClientBinder::StreamOut_get_presentation_position(const struct audio_stream_out* stream, uint64_t* frames, struct timespec* timestamp) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    void* stream_out_info = (audio_stream_out_to_client(stream))->stream_out_info;
    send.write(&stream_out_info, sizeof(stream_out_info));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SO_GPP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream out get presentation position", transactRet);

    int ret = reply.readInt32();

    *frames = reply.readUint64();
    timestamp->tv_sec = reply.readInt64();
    reply.read(&timestamp->tv_nsec, sizeof(timestamp->tv_nsec));

    return ret;
}

int AudioClientBinder::StreamIn_set_gain(struct audio_stream_in* stream, float gain) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    void* stream_in_info = (audio_stream_in_to_client(stream))->stream_in_info;
    send.write(&stream_in_info, sizeof(stream_in_info));

    send.writeFloat(gain);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SI_SG, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream in set gain", transactRet);

    return reply.readInt32();
}

ssize_t AudioClientBinder::StreamIn_read(struct audio_stream_in* stream, void* buffer, size_t bytes) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    audio_stream_in_client_t* stream_in_client = audio_stream_in_to_client(stream);

    void* stream_in_info = stream_in_client->stream_in_info;
    send.write(&stream_in_info, sizeof(stream_in_info));

    send.write(&bytes, sizeof(bytes));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SI_R, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream in read", transactRet);

    ssize_t ret = reply.readInt32();
    if (ret > 0) {
        std::lock_guard<std::mutex> lock(stream_in_client->stream_mutex);

        if (stream_in_client->shm == nullptr) {
            std::cout << PROCESS_NAME_LOG << " Shared memory to " << INPUT_STREAM_LABEL << " " << stream_in_client->name << " was not previously allocated on client. Allocating." << std::endl;
            setShmAndFdForStreamInClient(stream_in_client);
        }
        memcpy(buffer, stream_in_client->shm, ret);
    }

    return ret;
}

uint32_t AudioClientBinder::StreamIn_get_input_frames_lost(struct audio_stream_in* stream) {
    void* stream_in_info = (audio_stream_in_to_client(stream))->stream_in_info;
    return transactDataRetNum<void*, uint32_t>(stream_in_info, CMD_AS_SI_GIFL, "data for stream in get input frames lost");
}

int AudioClientBinder::StreamIn_get_capture_position(const struct audio_stream_in* stream, int64_t* frames, int64_t* time) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    void* stream_in_info = (audio_stream_in_to_client(stream))->stream_in_info;
    send.write(&stream_in_info, sizeof(stream_in_info));

    int transactRet = mAudioServiceBinder->transact(CMD_AS_SI_GCP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for stream in get capture position", transactRet);

    int ret = reply.readInt32();

    *frames = reply.readInt64();
    *time = reply.readInt64();

    return ret;
}

int AudioClientBinder::Service_ping(int& status_32) {
    const char* status_32_c_str;
    int ret = transactNoDataRetNumGetRef<int, const char*>(status_32_c_str, CMD_AS_SP, "for service ping");
    status_32 = std::stoi(status_32_c_str);
    return ret;
}

int AudioClientBinder::Effect_set_parameters(aml_audio_effect_type_e type, effect_param_t* param) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    uint32_t psize = ((param->psize - 1) / sizeof(int) + 1) * sizeof(int) + param->vsize;

    int typeTransact = type;
    send.writeInt32(typeTransact);

    uint32_t cmd_size = sizeof(effect_param_t) + psize;
    send.writeUint32(cmd_size);

    void* cmd_data = (void*)param;
    send.write(cmd_data, cmd_size);

    uint32_t reply_size = sizeof(int);
    send.writeUint32(reply_size);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_ESP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for effect set parameters", transactRet);

    param->status = reply.readUint32();

    return reply.readInt32();
}

int AudioClientBinder::Effect_get_parameters(aml_audio_effect_type_e type, effect_param_t* param) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    uint32_t psize = sizeof(effect_param_t) + ((param->psize - 1) / sizeof(int) + 1) * sizeof(int)
                        + param->vsize;

    int typeTransact = type;
    send.writeInt32(typeTransact);

    uint32_t cmd_size = sizeof(effect_param_t) + param->psize;
    send.writeUint32(cmd_size);

    void* cmd_data = (void*)param;
    send.write(cmd_data, cmd_size);

    uint32_t reply_size = psize;
    send.writeUint32(reply_size);

    int transactRet = mAudioServiceBinder->transact(CMD_AS_EGP, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, "data for effect get parameters", transactRet);

    int ret = reply.readInt32();
    if (!ret) {
        reply_size = reply.readUint32();
        void* reply_data = malloc(reply_size); reply.read(reply_data, reply_size);
        memcpy(param, reply_data, reply_size);

        free(reply_data);
        reply_data = nullptr;
    }
    return ret;
}

void AudioClientBinder::writeAudioConfigToParcel(const struct audio_config* config, ::android::Parcel& parcel) {
    uint32_t sample_rate_channel_mask_frame_count[3];
    sample_rate_channel_mask_frame_count[0] = config->sample_rate;
    sample_rate_channel_mask_frame_count[1] = config->channel_mask;
    sample_rate_channel_mask_frame_count[2] = config->frame_count;
    parcel.write(sample_rate_channel_mask_frame_count, sizeof(sample_rate_channel_mask_frame_count));
    parcel.writeInt32(config->format);
}

void AudioClientBinder::writeAudioPortConfigToParcel(const struct audio_port_config* config, ::android::Parcel& parcel) {
    parcel.writeInt32(config->id);
    parcel.writeInt32(config->role);

    audio_port_type_t type = config->type;
    parcel.writeInt32(type);

    parcel.writeUint32(config->config_mask);
    parcel.writeUint32(config->sample_rate);
    parcel.writeUint32(config->channel_mask);
    parcel.writeInt32(config->format);

    struct audio_gain_config gain = config->gain;
    parcel.writeInt32(gain.index);
    parcel.writeUint32(gain.mode);
    parcel.writeInt32(gain.channel_mask);

    parcel.write(gain.values, sizeof(gain.values));

    parcel.writeUint32(gain.ramp_duration_ms);

    if (type == AUDIO_PORT_TYPE_DEVICE) {
        struct audio_port_config_device_ext device = config->ext.device;
        parcel.writeInt32(device.hw_module);
        parcel.writeUint32(device.type);
        parcel.writeCString(AUDIO_PORT_TYPE_DEVICE_ADDRESS);
    } else if (type == AUDIO_PORT_TYPE_MIX) {
        struct audio_port_config_mix_ext mix = config->ext.mix;
        parcel.writeInt32(mix.hw_module);
        parcel.writeInt32(mix.handle);
        parcel.writeInt32(mix.usecase.stream);
    } else if (type == AUDIO_PORT_TYPE_SESSION) {
        parcel.writeInt32(config->ext.session.session);
    }
}

void AudioClientBinder::writeAudioPortConfigsToParcel(unsigned int numConfigs, const struct audio_port_config* configs, ::android::Parcel& parcel) {
    const struct audio_port_config* config = configs;
    for (unsigned int i = 0; i < numConfigs; i++, config++) {
        writeAudioPortConfigToParcel(config, parcel);
    }
}

void AudioClientBinder::transactNoData(transact_code code, const std::string& dataLabel) {
    CHK_SERVICE();

    ::android::Parcel send, reply;
    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET(transactRet, dataLabel);
}

template<typename T> void AudioClientBinder::transactData(const T& data, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE();

    ::android::Parcel send, reply;
    acb::writeDataToParcel<T>(data, send);

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET(transactRet, dataLabel);
}

template<typename R> R AudioClientBinder::transactNoDataRetNum(transact_code code, const std::string& dataLabel) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, dataLabel, transactRet);

    return acb::readDataFromParcel<R>(reply);
}

template<typename T, typename R> R AudioClientBinder::transactDataRetNum(const T& data, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;
    acb::writeDataToParcel<T>(data, send);

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, dataLabel, transactRet);

    return acb::readDataFromParcel<R>(reply);
}

template<typename REF> void AudioClientBinder::transactNoDataGetRef(REF& dataRef, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE();

    ::android::Parcel send, reply;

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET(transactRet, dataLabel);

    dataRef = acb::readDataFromParcel<REF>(reply);
}

template<typename T, typename REF> void AudioClientBinder::transactDataGetRef(const T& data, REF& dataRef, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE();

    ::android::Parcel send, reply;
    acb::writeDataToParcel<T>(data, send);

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET(transactRet, dataLabel);

    dataRef = acb::readDataFromParcel<REF>(reply);
}

template<typename R, typename REF> R AudioClientBinder::transactNoDataRetNumGetRef(REF& dataRef, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, dataLabel, transactRet);

    R ret = acb::readDataFromParcel<R>(reply);
    dataRef = acb::readDataFromParcel<REF>(reply);
    return ret;
}

template<typename T, typename R, typename REF> R AudioClientBinder::transactDataRetNumGetRef(const T& data, REF& dataRef, transact_code code, const std::string& dataLabel) {
    CHK_SERVICE_AND_RET(-1);

    ::android::Parcel send, reply;
    acb::writeDataToParcel<T>(data, send);

    int transactRet = mAudioServiceBinder->transact(code, send, &reply);
    CHK_TRANSACT_RET_AND_RET(transactRet, dataLabel, transactRet);

    R ret = acb::readDataFromParcel<R>(reply);
    dataRef = acb::readDataFromParcel<REF>(reply);
    return ret;
}

std::atomic_int AudioClientBinder::stream_seq_;

int AudioClientBinder::new_stream_name(char* name, size_t size) {
    int pid = ::getpid();
    int seq = (stream_seq_++);
    snprintf(name, size, "%d-%d", pid, seq);
    std::cout << PROCESS_NAME_LOG << " pid=" << pid << " seq=" << seq << " name=" << name << std::endl;
    return seq;
}

void AudioClientBinder::update_stream_name(char *name, size_t size, int id) {
    int pid = ::getpid();
    if ((id != pid) && (id > 0)) {
        int seq;
        if (sscanf(name, "%d-%d", &pid, &seq) == 2) {
            std::cout << PROCESS_NAME_LOG << " vpid " << pid << " -> pid " << id << std::endl;
            snprintf(name, size, "%d-%d", id, seq);
        }
    }
}

void AudioClientBinder::cleanStreamoutClients() {
    for (std::unordered_map<std::string, audio_stream_out_client_t*>::iterator it = streamoutClients.begin(); it != streamoutClients.end(); ++it) {

        const char* name = it->first.c_str();
        std::cout << PROCESS_NAME_LOG << " " OUTPUT_STREAM_LABEL << " " << name << " was opened." << std::endl;

        audio_stream_out_client_t* stream_out_client = it->second;
        if (stream_out_client != nullptr) {
            {
                std::lock_guard<std::mutex> lock(stream_out_client->stream_mutex);
                posixCloseFile(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, name, stream_out_client->fd);
            }
            delete stream_out_client;
            stream_out_client = nullptr;
        }
    }

    streamoutClients.clear();
}

void AudioClientBinder::cleanStreaminClients() {
    for (std::unordered_map<std::string, audio_stream_in_client_t*>::iterator it = streaminClients.begin(); it != streaminClients.end(); ++it) {

        const char* name = it->first.c_str();
        std::cout << PROCESS_NAME_LOG << " " INPUT_STREAM_LABEL << " " << name << " was opened." << std::endl;

        audio_stream_in_client_t* stream_in_client = it->second;
        if (stream_in_client != nullptr) {
            {
                std::lock_guard<std::mutex> lock(stream_in_client->stream_mutex);
                posixCloseFile(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, name, stream_in_client->fd);
            }
            delete stream_in_client;
            stream_in_client = nullptr;
        }
    }

    streaminClients.clear();
}

int AudioClientBinder::updateStreamOutClient(const ::android::Parcel& reply, audio_stream_out_client_t* stream_out_client) {
    int clientId = reply.readInt32();
    update_stream_name(stream_out_client->name, sizeof(stream_out_client->name), clientId);

    reply.read(&(stream_out_client->stream_hw), sizeof(stream_out_client->stream_hw));
    reply.read(&(stream_out_client->stream_out_info), sizeof(stream_out_client->stream_out_info));

    {
        std::lock_guard<std::mutex> lock(stream_out_client->stream_mutex);
        return setShmAndFdForStreamOutClient(stream_out_client);
    }
}

int AudioClientBinder::updateStreamInClient(const ::android::Parcel& reply, audio_stream_in_client_t* stream_in_client) {
    int clientId = reply.readInt32();
    update_stream_name(stream_in_client->name, sizeof(stream_in_client->name), clientId);

    reply.read(&(stream_in_client->stream_hw), sizeof(stream_in_client->stream_hw));
    reply.read(&(stream_in_client->stream_in_info), sizeof(stream_in_client->stream_in_info));

    {
        std::lock_guard<std::mutex> lock(stream_in_client->stream_mutex);
        return setShmAndFdForStreamInClient(stream_in_client);
    }
}

int AudioClientBinder::setShmAndFdForStreamOutClient(audio_stream_out_client_t* stream_out_client) {
    int fd; void* streamoutShm = nullptr;

    fd = posixOpenFileAndMapData(PROCESS_NAME_LOG, OUTPUT_STREAM_LABEL, stream_out_client->name, O_RDWR, S_IRUSR | S_IWUSR, streamoutShm, KSHAREDBUFFERSIZE, PROT_READ | PROT_WRITE, MAP_SHARED);
    if (fd == -1) {
        return -1;
    }
    stream_out_client->fd = fd;
    stream_out_client->shm = streamoutShm;
    return 0;
}

int AudioClientBinder::setShmAndFdForStreamInClient(audio_stream_in_client_t* stream_in_client) {
    int fd; void* streaminShm = nullptr;
    fd = posixOpenFileAndMapData(PROCESS_NAME_LOG, INPUT_STREAM_LABEL, stream_in_client->name, O_RDWR, S_IRUSR | S_IWUSR, streaminShm, KSHAREDBUFFERSIZE, PROT_READ | PROT_WRITE, MAP_SHARED);
    if (fd == -1) {
        return -1;
    }
    stream_in_client->fd = fd;
    stream_in_client->shm = streaminShm;
    return 0;
}