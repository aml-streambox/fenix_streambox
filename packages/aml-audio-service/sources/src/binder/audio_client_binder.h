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

#ifndef AUDIO_CLIENT_BINDER_H
#define AUDIO_CLIENT_BINDER_H

#include <binder/Binder.h>
#include <binder/Parcel.h>
#include <binder/IServiceManager.h>

#include <memory>

#include "audio_effect_if.h"
#include "common.h"

typedef struct audio_stream_client {
    char name[32];
    void* stream_hw;
    struct audio_stream stream;
} audio_stream_client_t;

typedef struct audio_stream_out_client {
    char name[32];
    void* stream_hw;
    struct audio_stream_out stream_out;
    void* stream_out_info;
    std::mutex stream_mutex;
    int fd;
    void* shm;
} audio_stream_out_client_t;

typedef struct audio_stream_in_client {
    char name[32];
    void* stream_hw;
    struct audio_stream_in stream_in;
    void* stream_in_info;
    std::mutex stream_mutex;
    int fd;
    void* shm;
} audio_stream_in_client_t;

template< class T, class M >
static inline constexpr ptrdiff_t offset_of( const M T::*member ) {
    return reinterpret_cast< ptrdiff_t >( &( reinterpret_cast< T* >( 0 )->*member ) );
}

template< class T, class M >
static inline T* container_of( const M *ptr, const M T::*member ) {
    return reinterpret_cast< T* >( reinterpret_cast< intptr_t >( ptr ) - offset_of( member ) );
}

inline audio_stream_in_client_t* audio_stream_in_to_client(const audio_stream_in* p)
{
    return container_of(p, &audio_stream_in_client::stream_in);
}

inline audio_stream_out_client_t* audio_stream_out_to_client(const audio_stream_out* p)
{
    return container_of(p, &audio_stream_out_client::stream_out);
}

inline audio_stream_client_t* audio_stream_to_client(const audio_stream* p)
{
    return container_of(p, &audio_stream_client::stream);
}

class ClientDeathRecipient;

class AudioClientBinder : public ::android::BBinder {
    public:
        AudioClientBinder();

        void setspInstance(::android::sp<AudioClientBinder> spInstance);
        void gc();

        bool gotService();

        void on_service_exception();    // service exception includes the case in which service turns off

        /* service methods */
        int Device_common_close();

        ////////////////////////////
        // Device API
        ////////////////////////////

        int Device_init_check();
        int Device_set_voice_volume(float volume);
        int Device_set_master_volume(float volume);
        int Device_get_master_volume(float& masterVolume);
        int Device_set_mode(audio_mode_t mode);
        int Device_set_mic_mute(bool state);
        int Device_get_mic_mute(bool& state);
        int Device_set_parameters(const char* kv_pairs);
        char* Device_get_parameters(const char* keys);
        size_t Device_get_input_buffer_size(const struct audio_config* config);
        int Device_open_output_stream(audio_io_handle_t handle,
                                    audio_devices_t devices,
                                    audio_output_flags_t flags,
                                    struct audio_config* config,
                                    audio_stream_out_client_t*& stream_out_client,
                                    const char* address);
        void Device_close_output_stream(struct audio_stream_out* stream_out);
        int Device_open_input_stream(audio_io_handle_t handle,
                                    audio_devices_t devices,
                                    struct audio_config* config,
                                    audio_stream_in_client_t*& stream_in_client,
                                    audio_input_flags_t flags,
                                    const char *address,
                                    audio_source_t source);
        void Device_close_input_stream(struct audio_stream_in* stream_in);
        int Device_dump(std::string& deviceDump);
        int Device_set_master_mute(bool mute);
        int Device_get_master_mute(bool& mute);
        int Device_create_audio_patch(unsigned int num_sources, const struct audio_port_config* sources, unsigned int num_sinks, const struct audio_port_config* sinks, audio_patch_handle_t* handle);
        int Device_release_audio_patch(audio_patch_handle_t handle);
        int Device_set_audio_port_config(const struct audio_port_config* config);

        ////////////////////////////
        // Stream API
        ////////////////////////////

        uint32_t Stream_get_sample_rate(const struct audio_stream* stream);
        size_t Stream_get_buffer_size(const struct audio_stream* stream);
        audio_channel_mask_t Stream_get_channels(const struct audio_stream* stream);
        audio_format_t Stream_get_format(const struct audio_stream* stream);
        int Stream_standby(struct audio_stream* stream);
        audio_devices_t Stream_get_device(const struct audio_stream* stream);
        int Stream_set_parameters(struct audio_stream* stream, const char* kv_pairs);
        char* Stream_get_parameters(const struct audio_stream* stream, const char* keys);

        ////////////////////////////
        // Stream Out API
        ////////////////////////////

        uint32_t StreamOut_get_latency(const struct audio_stream_out* stream);
        int StreamOut_set_volume(struct audio_stream_out* stream, float left, float right);
        ssize_t StreamOut_write(struct audio_stream_out* stream, const void* buffer, size_t bytes);
        int StreamOut_get_render_position(const struct audio_stream_out* stream, uint32_t* dsp_frames);
        int StreamOut_get_next_write_timestamp(const struct audio_stream_out* stream, int64_t* timestamp);
        int StreamOut_pause(struct audio_stream_out* stream);
        int StreamOut_resume(struct audio_stream_out* stream);
        int StreamOut_flush(struct audio_stream_out* stream);
        int StreamOut_get_presentation_position(const struct audio_stream_out* stream, uint64_t* frames, struct timespec* timestamp);

        ////////////////////////////
        // Stream In API
        ////////////////////////////

        int StreamIn_set_gain(struct audio_stream_in* stream, float gain);
        ssize_t StreamIn_read(struct audio_stream_in* stream, void* buffer, size_t bytes);
        uint32_t StreamIn_get_input_frames_lost(struct audio_stream_in* stream);
        int StreamIn_get_capture_position(const struct audio_stream_in* stream, int64_t* frames, int64_t* time);

        ////////////////////////////
        // Misc API
        ////////////////////////////

        int Service_ping(int& status_32);

        ////////////////////////////
        // Effect API
        ////////////////////////////

        int Effect_set_parameters(aml_audio_effect_type_e type, effect_param_t* param);
        int Effect_get_parameters(aml_audio_effect_type_e type, effect_param_t* param);

    private:
        ::android::sp<AudioClientBinder> spInstance_;
        ::android::sp<::android::IBinder> mAudioServiceBinder;

        static std::mutex on_service_exception_mutex_;
        ::android::sp<ClientDeathRecipient> clientDeathRecipient;

        int numTries = 0;
        const std::string PROCESS_NAME_LOG = processNameLogs.AUDIO_CLIENT_BINDER;
        bool mService = false;

        static std::atomic_int stream_seq_;

        static std::mutex stream_out_clients_mutex_;
        std::unordered_map<std::string, audio_stream_out_client_t*> streamoutClients;

        static std::mutex stream_in_clients_mutex_;
        std::unordered_map<std::string, audio_stream_in_client_t*> streaminClients;

        void writeAudioConfigToParcel(const struct audio_config* config, ::android::Parcel& parcel);
        void writeAudioPortConfigToParcel(const struct audio_port_config* config, ::android::Parcel& parcel);
        void writeAudioPortConfigsToParcel(unsigned int numConfigs, const struct audio_port_config* configs, ::android::Parcel& parcel);

        // T - data type, R - return type (not reference), REF - reference type
        void transactNoData(transact_code code, const std::string& dataLabel);
        template<typename T> void transactData(const T& data, transact_code code, const std::string& dataLabel);
        template<typename R> R transactNoDataRetNum(transact_code code, const std::string& dataLabel);
        template<typename T, typename R> R transactDataRetNum(const T& data, transact_code code, const std::string& dataLabel);
        template<typename REF> void transactNoDataGetRef(REF& dataRef, transact_code code, const std::string& dataLabel);
        template<typename T, typename REF> void transactDataGetRef(const T& data, REF& dataRef, transact_code code, const std::string& dataLabel);
        template<typename R, typename REF> R transactNoDataRetNumGetRef(REF& dataRef, transact_code code, const std::string& dataLabel);

        // reads reply Parcel for return value, then reference in that order
        template<typename T, typename R, typename REF> R transactDataRetNumGetRef(const T& data, REF& dataRef, transact_code code, const std::string& dataLabel);

        int new_stream_name(char* name, size_t size);
        void update_stream_name(char* name, size_t size, int id);

        void cleanStreamoutClients();
        void cleanStreaminClients();
        int updateStreamOutClient(const ::android::Parcel& reply, audio_stream_out_client_t* stream_out_client);
        int updateStreamInClient(const ::android::Parcel& reply, audio_stream_in_client_t* stream_in_client);
        int setShmAndFdForStreamOutClient(audio_stream_out_client_t* stream_out_client);
        int setShmAndFdForStreamInClient(audio_stream_in_client_t* stream_in_client);

        virtual ::android::status_t onTransact(uint32_t code, const ::android::Parcel& data, ::android::Parcel* reply, uint32_t flags = 0) { return (0); }
};

#endif  // AUDIO_CLIENT_BINDER_H
