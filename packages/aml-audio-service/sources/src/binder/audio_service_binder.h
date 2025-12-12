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

#ifndef AUDIO_SERVICE_BINDER_H
#define AUDIO_SERVICE_BINDER_H

#include <binder/Binder.h>
#include <binder/Parcel.h>
#include <binder/IPCThreadState.h>

#include <unordered_set>

#include "audio_effect_if.h"
#include "common.h"

typedef struct audio_stream_out_info {
    char name[32];
    struct audio_stream_out* stream_out_hw;
    std::mutex stream_mutex;
    int fd;
    void* shm;
} audio_stream_out_info_t;

typedef struct audio_stream_in_info {
    char name[32];
    struct audio_stream_in* stream_in_hw;
    std::mutex stream_mutex;
    int fd;
    void* shm;
} audio_stream_in_info_t;

class ServiceDeathRecipient;

typedef std::pair<audio_stream_direction, void*> stream_data_t;
typedef std::pair<::android::sp<ServiceDeathRecipient>, std::unordered_map<std::string, stream_data_t> > gc_stream_map_t;

class AudioServiceBinder : public ::android::BBinder {
    public:
        AudioServiceBinder();
        ~AudioServiceBinder();
        static AudioServiceBinder* GetInstance();

        void on_client_turned_off(int clientPid);

    private:
        const std::string PROCESS_NAME_LOG = processNameLogs.AUDIO_SERVICE_BINDER;
        static AudioServiceBinder* mInstance;

        /* audio hal interface */
        struct audio_hw_device* dev_;
        audio_effect_t* effect_;

        static std::mutex gc_map_mutex_;
        std::unordered_map<int, gc_stream_map_t> gc_stream_map_;

        std::unordered_set<audio_patch_handle_t> audioPatchHandles;

        /* service methods */
        int Device_common_close();

        ////////////////////////////
        // Device API
        ////////////////////////////

        // check to see if the audio hardware interface has been initialized.
        // returns 0 on success, -ENODEV on failure.
        int Device_init_check();

        // set the audio volume of a voice call. Range is between 0.0 and 1.0
        int Device_set_voice_volume(float volume);

        // set the audio volume for all audio activities other than voice call.
        // Range between 0.0 and 1.0. If any value other than 0 is returned,
        // the software mixer will emulate this capability.
        int Device_set_master_volume(float volume);

        // Get the current master volume value for the HAL, if the HAL supports
        // master volume control.  AudioFlinger will query this value from the
        // primary audio HAL when the service starts and use the value for setting
        // the initial master volume across all HALs.  HALs which do not support
        // this method may leave it set to NULL.
        int Device_get_master_volume(float& masterVolume);

        // set_mode is called when the audio mode changes. AUDIO_MODE_NORMAL mode
        // is for standard audio playback, AUDIO_MODE_RINGTONE when a ringtone is
        // playing, and AUDIO_MODE_IN_CALL when a call is in progress.
        int Device_set_mode(audio_mode_t mode);

        // mic mute
        int Device_set_mic_mute(bool state);
        int Device_get_mic_mute(bool& state);

        // set/get global audio parameters
        int Device_set_parameters(const char* kv_pairs);
        char* Device_get_parameters(const char* keys);

        // Returns audio input buffer size according to parameters passed or
        // 0 if one of the parameters is not supported.
        // See also get_buffer_size which is for a particular stream.
        int Device_get_input_buffer_size(const struct audio_config& config);

        // This method creates and opens the audio hardware output stream.
        // The "address" parameter qualifies the "devices" audio device type if needed.
        // The format format depends on the device type:
        // - Bluetooth devices use the MAC address of the device in the form "00:11:22:AA:BB:CC"
        // - USB devices use the ALSA card and device numbers in the form  "card=X;device=Y"
        // - Other devices may use a number or any other string.
        int Device_open_output_stream(::android::sp<::android::IBinder> audioClientBinder,
                                    int seq,
                                    audio_io_handle_t handle,
                                    audio_devices_t devices,
                                    audio_output_flags_t flags,
                                    struct audio_config& config,
                                    const char* address,
                                    int& clientId,
                                    struct audio_stream*& stream_hw,
                                    audio_stream_out_info_t*& stream_out_info);
        void Device_close_output_stream(audio_stream_out_info_t* stream_out_info);

        // This method creates and opens the audio hardware input stream
        int Device_open_input_stream(::android::sp<::android::IBinder> audioClientBinder,
                                int seq,
                                audio_io_handle_t handle,
                                audio_devices_t devices,
                                struct audio_config& config,
                                audio_input_flags_t flags,
                                const char* address,
                                audio_source_t source,
                                int& clientId,
                                struct audio_stream*& stream_hw,
                                audio_stream_in_info_t*& stream_in_info);
        void Device_close_input_stream(audio_stream_in_info_t* stream_in_info);

        int Device_dump(std::string& deviceDump);

        // set the audio mute status for all audio activities.  If any value other
        // than 0 is returned, the software mixer will emulate this capability.
        int Device_set_master_mute(bool mute);
        int Device_get_master_mute(bool& mute);

        // Routing control
        // Creates an audio patch between several source and sink ports.
        // The handle is allocated by the HAL and should be unique for this
        // audio HAL module.
        int Device_create_audio_patch(unsigned int num_sources,
                                    const struct audio_port_config* sources,
                                    unsigned int num_sinks,
                                    const struct audio_port_config* sinks,
                                    audio_patch_handle_t& handle);
        int Device_release_audio_patch(audio_patch_handle_t handle);

        // Set audio port configuration
        int Device_set_audio_port_config(const struct audio_port_config& config);

        ////////////////////////////
        // Stream API
        ////////////////////////////

        // Return the sampling rate in Hz - eg. 44100.
        uint32_t Stream_get_sample_rate(struct audio_stream* stream_hw);

        // Return size of input/output buffer in bytes for this stream - eg. 4800.
        // It should be a multiple of the frame size.  See also get_input_buffer_size.
        size_t Stream_get_buffer_size(struct audio_stream* stream_hw);

        // Return the channel mask -
        //  e.g. AUDIO_CHANNEL_OUT_STEREO or AUDIO_CHANNEL_IN_STEREO
        uint32_t Stream_get_channels(struct audio_stream* stream_hw);

        // Return the audio format - e.g. AUDIO_FORMAT_PCM_16_BIT
        uint32_t Stream_get_format(struct audio_stream* stream_hw);

        // Put the audio hardware input/output into standby mode.
        // Driver should exit from standby mode at the next I/O operation.
        // Returns 0 on success and <0 on failure.
        uint32_t Stream_standby(struct audio_stream* stream_hw);

        // Return the set of device(s) which this stream is connected to
        uint32_t Stream_get_device(struct audio_stream* stream_hw);

        // set/get audio stream parameters. The function accepts a list of
        // parameter key value pairs in the form: key1=value1;key2=value2;...
        //
        // Some keys are reserved for standard parameters (See AudioParameter class)
        //
        // If the implementation does not accept a parameter change while
        // the output is active but the parameter is acceptable otherwise, it must
        // return -ENOSYS.
        //
        // The audio flinger will put the stream in standby and then change the
        // parameter value.
        int Stream_set_parameters(struct audio_stream* stream_hw, const char* kv_pairs);

        char* Stream_get_parameters(struct audio_stream* stream_hw, const char* keys);

        ////////////////////////////
        // Stream Out API
        ////////////////////////////

        // Return the audio hardware driver estimated latency in milliseconds.
        uint32_t StreamOut_get_latency(struct audio_stream_out* stream_out_hw);

        // Use this method in situations where audio mixing is done in the
        // hardware. This method serves as a direct interface with hardware,
        // allowing you to directly set the volume as apposed to via the framework.
        // This method might produce multiple PCM outputs or hardware accelerated
        // codecs, such as MP3 or AAC.
        int StreamOut_set_volume(struct audio_stream_out* stream_out_hw, float left, float right);

        // Write audio buffer to driver. Returns number of bytes written, or a
        // negative status_t. If at least one frame was written successfully prior to the error,
        // it is suggested that the driver return that successful (short) byte count
        // and then return an error in the subsequent call.
        //
        // If set_callback() has previously been called to enable non-blocking mode
        // the write() is not allowed to block. It must write only the number of
        // bytes that currently fit in the driver/hardware buffer and then return
        // this byte count. If this is less than the requested write size the
        // callback function must be called when more space is available in the
        // driver/hardware buffer.
        ssize_t StreamOut_write(audio_stream_out_info_t* stream_out_info, size_t bytes);

        // return the number of audio frames written by the audio dsp to DAC since
        // the output has exited standby
        int StreamOut_get_render_position(struct audio_stream_out* stream_out_hw, uint32_t& dsp_frames);

        // get the local time at which the next write to the audio driver will be presented.
        // The units are microseconds, where the epoch is decided by the local audio HAL.
        int StreamOut_get_next_write_timestamp(struct audio_stream_out* stream_out_hw, int64_t& timestamp);

        // Notifies to the audio driver to stop playback however the queued buffers are
        // retained by the hardware. Useful for implementing pause/resume. Empty implementation
        // if not supported however should be implemented for hardware with non-trivial
        // latency. In the pause state audio hardware could still be using power. User may
        // consider calling suspend after a timeout.
        //
        // Implementation of this function is mandatory for offloaded playback.
        int StreamOut_pause(struct audio_stream_out* stream_out_hw);

        // Notifies to the audio driver to resume playback following a pause.
        // Returns error if called without matching pause.
        //
        // Implementation of this function is mandatory for offloaded playback.
        int StreamOut_resume(struct audio_stream_out* stream_out_hw);

        // Notifies to the audio driver to flush the queued data. Stream must already
        // be paused before calling flush().
        //
        // Implementation of this function is mandatory for offloaded playback.
        int StreamOut_flush(struct audio_stream_out* stream_out_hw);

        // Return a recent count of the number of audio frames presented to an external observer.
        // This excludes frames which have been written but are still in the pipeline.
        // The count is not reset to zero when output enters standby.
        // Also returns the value of CLOCK_MONOTONIC as of this presentation count.
        // The returned count is expected to be 'recent',
        // but does not need to be the most recent possible value.
        // However, the associated time should correspond to whatever count is returned.
        // Example:  assume that N+M frames have been presented, where M is a 'small' number.
        // Then it is permissible to return N instead of N+M,
        // and the timestamp should correspond to N rather than N+M.
        // The terms 'recent' and 'small' are not defined.
        // They reflect the quality of the implementation.
        //
        // 3.0 and higher only.
        int StreamOut_get_presentation_position(struct audio_stream_out* stream_out_hw,
                                            uint64_t& frames,
                                            struct timespec& timestamp);

        ////////////////////////////
        // Stream In API
        ////////////////////////////
        // set the input gain for the audio driver. This method is for
        // for future use */
        // int (*set_gain)(struct audio_stream_in *stream, float gain);
        int StreamIn_set_gain(struct audio_stream_in* stream_in_hw, float gain);

        // Read audio buffer in from audio driver. Returns number of bytes read, or a
        // negative status_t. If at least one frame was read prior to the error,
        // read should return that byte count and then return an error in the subsequent call.
        int StreamIn_read(audio_stream_in_info_t* stream_in_info, size_t bytes);

        // Return the amount of input frames lost in the audio driver since the
        // last call of this function.
        // Audio driver is expected to reset the value to 0 and restart counting
        // upon returning the current value by this function call.
        // Such loss typically occurs when the user space process is blocked
        // longer than the capacity of audio driver buffers.
        //
        // Unit: the number of input audio frames
        // uint32_t (*get_input_frames_lost)(struct audio_stream_in *stream);
        uint32_t StreamIn_get_input_frames_lost(struct audio_stream_in* stream_in_hw);

        // Return a recent count of the number of audio frames received and
        // the clock time associated with that frame count.
        //
        // frames is the total frame count received. This should be as early in
        //     the capture pipeline as possible. In general,
        //     frames should be non-negative and should not go "backwards".
        //
        // time is the clock MONOTONIC time when frames was measured. In general,
        //     time should be a positive quantity and should not go "backwards".
        //
        // The status returned is 0 on success, -ENOSYS if the device is not
        // ready/available, or -EINVAL if the arguments are null or otherwise invalid.
        int StreamIn_get_capture_position(struct audio_stream_in* stream_in_hw, int64_t& frames, int64_t& time);

        ////////////////////////////
        // Misc API
        ////////////////////////////

        int Service_ping(int& status_32);

        ////////////////////////////
        // Effect API
        ////////////////////////////

        // set/get audio effect parameters.
        int Effect_set_parameters(aml_audio_effect_type_e type,
                            uint32_t cmdSize,
                            void* pCmdData,
                            uint32_t replySize,
                            uint32_t& pReplyData);
        int Effect_get_parameters(aml_audio_effect_type_e type,
                            uint32_t cmdSize,
                            void* pCmdData,
                            uint32_t& replySize,
                            void* pReplyData);

        // garbage collection
        void stream_gc_(const std::unordered_map<std::string, stream_data_t>& streamsInfo);
        void streamout_gc_(std::mutex& stream_mutex, const char* name, void* shm, int fd, audio_stream_out* stream_out_hw);
        void streamin_gc_(std::mutex& stream_mutex, const char* name, void* shm, int fd, audio_stream_in* stream_in_hw);

        /* helper methods */
        int updateStreamOutInfo(const char* name, struct audio_stream_out* stream, audio_stream_out_info_t* stream_out_info);
        int updateStreamInInfo(const char* name, struct audio_stream_in* stream, audio_stream_in_info_t* stream_in_info);
        int setShmAndFdForStreamOutInfo(const char* name, audio_stream_out_info_t* stream_out_info);
        int setShmAndFdForStreamInInfo(const char* name, audio_stream_in_info_t* stream_in_info);

        void update_gc_stream_map(::android::sp<::android::IBinder> audioClientBinder,
                                int client_id,
                                const std::string& stream_id,
                                audio_stream_direction streamDirection,
                                void* streamInfo);
        void remove_stream_info_from_gc_stream_map(int clientPid, const std::string& name);

        void readAudioConfigFromParcel(struct audio_config& config, const ::android::Parcel& parcel);
        void readAudioPortConfigFromParcel(struct audio_port_config& config, const ::android::Parcel& parcel);
        void readAudioPortConfigsFromParcel(unsigned int numConfigs, struct audio_port_config* configs, const ::android::Parcel& parcel);

        /* binder api method */
        virtual ::android::status_t onTransact(uint32_t code, const ::android::Parcel& data, ::android::Parcel* reply, uint32_t flags = 0);
};
#endif  // AUDIO_SERVICE_BINDER_H