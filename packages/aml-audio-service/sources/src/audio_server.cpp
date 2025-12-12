#include <stdio.h>
#include <execinfo.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <grp.h>
#include <sys/un.h>
#include <sys/socket.h>
#include <sys/stat.h>

#include <boost/interprocess/managed_shared_memory.hpp>
#include <cstdlib>
#include <iomanip>
#include <mutex>
#include <chrono>
#include <condition_variable>
#include <thread>
#include <signal.h>

#define LOG_TAG "audio_server"
#include <cutils/log.h>

#include <grpc/grpc.h>
#include <grpcpp/server.h>
#include <grpcpp/server_builder.h>
#include <grpcpp/server_context.h>
#include <grpcpp/server_posix.h>
#include <grpcpp/security/server_credentials.h>
#include <IpcBuffer/audio_server_shmem.h>
#include <IpcBuffer/IpcBuffer.h>
#include "audio_if.h"
#include "audio_service.grpc.pb.h"
#include "audio_effect_if.h"

using grpc::Server;
using grpc::ServerBuilder;
using grpc::ServerContext;
using grpc::ServerReader;
using grpc::ServerReaderWriter;
using grpc::ServerWriter;
using grpc::Status;
using audio_service::StatusReturn;
using audio_service::Volume;
using audio_service::Mode;
using audio_service::Mute;
using audio_service::Kv_pairs;
using audio_service::Keys;
using audio_service::Handle;
using audio_service::OpenOutputStream;
using audio_service::Stream;
using audio_service::OpenInputStream;
using audio_service::CreateAudioPatch;
using audio_service::AudioPortConfig;
using audio_service::AudioGainConfig;
using audio_service::AudioPortConfigDeviceExt;
using audio_service::AudioPortConfigMixExt;
using audio_service::AudioPortConfigSessionExt;
using audio_service::StreamSetParameters;
using audio_service::StreamGetParameters;
using audio_service::StreamAudioEffect;
using audio_service::StreamOutSetVolume;
using audio_service::StreamReadWrite;
using audio_service::GetFrameTimestampReturn;
using audio_service::StreamGain;
using audio_service::EffectParameters;
using google::protobuf::Empty;

using namespace boost::interprocess;
using namespace audio_service;

//#define DEBUG__

#ifdef DEBUG__
#define TRACE_ENTRY() ALOGI("%s enter\n", __func__)
#define TRACE_EXIT() ALOGI("%s exit\n", __func__)
#else
#define TRACE_ENTRY()
#define TRACE_EXIT()
#endif

typedef std::pair<IpcBuffer *, struct audio_stream_out *> streamout_map_t;
typedef std::pair<IpcBuffer *, struct audio_stream_in *> streamin_map_t;

class AudioServiceImpl final : public AudioService::Service
{
  public:
    explicit AudioServiceImpl()
      : shm_(audio_server_shmem::getInstance(true)),
        gc_runner_stop_(false),
        gc_runner_(std::thread([this] {
          while (!gc_runner_stop_) {
            streamout_gc_();
            streamin_gc_();

            std::unique_lock<std::mutex> lock(gc_mutex_);
            gc_cv_.wait_for(lock, std::chrono::milliseconds(500), [this]() { return gc_runner_stop_; });
          }
        })) {
        if (audio_hw_load_interface(&dev_) == 0) {
          if (dev_) {
            effect_ = (audio_effect_t *)dev_->common.reserved[0];
          }
          //ALOGI(__func__, "[AudioServer] Get audio hal interface successfully.\n");
        }
      }

    ~AudioServiceImpl() {
      {
        std::lock_guard<std::mutex> lock(gc_mutex_);
        gc_runner_stop_ = true;
      }
      gc_cv_.notify_one();
      gc_runner_.join();
      if (dev_) {
        if (effect_) {
          effect_ = nullptr;
        }
        audio_hw_unload_interface(dev_);
        dev_ = nullptr;
      }
    }

    Status Device_common_close(ServerContext* context, const Empty* empty, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->common.close(&dev_->common));
      return Status::OK;
    }

    Status Device_init_check(ServerContext* context, const Empty* empty, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->init_check(dev_));
      return Status::OK;
    }

    Status Device_set_voice_volume(ServerContext* context, const Volume* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_voice_volume(dev_, request->vol()));
      return Status::OK;
    }

    Status Device_set_master_volume(ServerContext* context, const Volume* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_master_volume(dev_, request->vol()));
      return Status::OK;
    }

    Status Device_get_master_volume(ServerContext* context, const Empty* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      float vol = 0.0;
      response->set_ret(dev_->get_master_volume(dev_, &vol));
      response->set_status_float(vol);
      return Status::OK;
    }

    Status Device_set_mode(ServerContext* context, const Mode* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_mode(dev_, (audio_mode_t)(request->mode())));
      return Status::OK;
    }

    Status Device_set_mic_mute(ServerContext* context, const Mute* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_mic_mute(dev_, request->mute()));
      return Status::OK;
    }

    Status Device_get_mic_mute(ServerContext* context, const Empty* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      bool mute = false;
      response->set_ret(dev_->get_mic_mute(dev_, &mute));
      response->set_status_bool(mute);
      return Status::OK;
    }

    Status Device_set_parameters(ServerContext* context, const Kv_pairs* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_parameters(dev_, request->params().c_str()));
      return Status::OK;
    }

    Status Device_get_parameters(ServerContext* context, const Keys* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      char *param = dev_->get_parameters(dev_, request->keys().c_str());
      response->set_ret(param ? 0 : -1);
      response->set_status_string(std::string(param));

      // param is heap allocated and need free in behalf of client
      free(param);

      return Status::OK;
    }

    Status Device_get_input_buffer_size(ServerContext* context, const AudioConfig* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_config config;
      config.sample_rate = request->sample_rate();
      config.channel_mask = request->channel_mask();
      config.format = (audio_format_t)(request->format());
      config.frame_count = request->frame_count();

      response->set_ret(dev_->get_input_buffer_size(dev_, &config));
      return Status::OK;
    }

    Status Device_open_output_stream(ServerContext* context, const OpenOutputStream* request, DeviceOpenStreamReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      int vpid, seq;
      if (sscanf(request->name().c_str(), "%d-%d", &vpid, &seq) != 2) {
        response->set_client_id(-1);
        return Status::CANCELLED;
      }
      int client_id = get_client_pid_(context);
      if (client_id < 0) {
        response->set_client_id(-1);
        return Status::CANCELLED;
      }
      char buf[32];
      snprintf(buf, sizeof(buf), "%d-%d", client_id, seq);
      std::string stream_id(buf);

      struct audio_stream_out *stream = nullptr;
      struct audio_config config;
      config.sample_rate = request->config().sample_rate();
      config.channel_mask = request->config().channel_mask();
      config.format = (audio_format_t)(request->config().format());
      config.frame_count = request->config().frame_count();

      streamout_gc_();

      response->set_ret(dev_->open_output_stream(dev_,
                          (audio_io_handle_t)(request->handle()),
                          (audio_devices_t)(request->devices()),
                          (audio_output_flags_t)(request->flags()),
                          &config,
                          &stream,
                          request->address().c_str()));
      response->set_client_id(client_id);

      if (stream) {
        IpcBuffer * cb = shm_->find<IpcBuffer>(stream_id.c_str()).first;
        if (cb == nullptr) {
          cb = shm_->construct<IpcBuffer>(stream_id.c_str())(stream_id.c_str(), request->size());
          std::cout << "[AudioServer] open stream pid-seq " << stream_id.c_str() << std::endl;
          ALOGI("%s pid-seq %s\n", __func__, stream_id.c_str());
        }

        std::lock_guard<std::mutex> lock(map_out_mutex_);
        streamout_map_.insert(
          std::pair<const std::string, streamout_map_t>(stream_id, streamout_map_t(cb, stream)));
      }

      return Status::OK;
    }

    Status Device_close_output_stream(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      std::map<const std::string, streamout_map_t >::iterator it = streamout_map_.find(request->name());
      if (it == streamout_map_.end()) return Status::CANCELLED;

      std::cout << "[AudioServer] close stream pid-seq " << request->name().c_str() << std::endl;
      ALOGI("%s pid-seq %s\n", __func__, request->name().c_str());
      dev_->close_output_stream(dev_, it->second.second);

      if (it->second.first) {
        shm_->destroy<IpcBuffer>(request->name().c_str());
      }

      std::lock_guard<std::mutex> lock(map_out_mutex_);
      streamout_map_.erase(it);

      TRACE_EXIT();

      return Status::OK;
    }

    Status Device_open_input_stream(ServerContext* context, const OpenInputStream* request, DeviceOpenStreamReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      int vpid, seq;
      if (sscanf(request->name().c_str(), "%d-%d", &vpid, &seq) != 2) {
        return Status::CANCELLED;
      }
      int client_id = get_client_pid_(context);
      if (client_id < 0) {
        return Status::CANCELLED;
      }
      char buf[32];
      snprintf(buf, sizeof(buf), "%d-%d", client_id, seq);
      std::string stream_id(buf);

      struct audio_stream_in *stream = nullptr;
      struct audio_config config;
      config.sample_rate = request->config().sample_rate();
      config.channel_mask = request->config().channel_mask();
      config.format = (audio_format_t)(request->config().format());
      config.frame_count = request->config().frame_count();

      streamin_gc_();

      response->set_ret(dev_->open_input_stream(dev_,
                          (audio_io_handle_t)(request->handle()),
                          (audio_devices_t)(request->devices()),
                          &config,
                          &stream,
                          (audio_input_flags_t)(request->flags()),
                          request->address().c_str(),
                          (audio_source_t)(request->source())));
      response->set_client_id(client_id);

      if (stream) {
        IpcBuffer * cb = shm_->find<IpcBuffer>(stream_id.c_str()).first;
        if (cb == nullptr)
          cb = shm_->construct<IpcBuffer>(stream_id.c_str())(request->name().c_str(), request->size());

        std::lock_guard<std::mutex> lock(map_in_mutex_);
        streamin_map_.insert(
          std::pair<const std::string, streamin_map_t>(stream_id, streamin_map_t(cb, stream)));
      }

      return Status::OK;
    }

    Status Device_close_input_stream(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      std::map<const std::string, streamin_map_t >::iterator it = streamin_map_.find(request->name());
      if (it == streamin_map_.end()) return Status::CANCELLED;

      dev_->close_input_stream(dev_, it->second.second);

      if (it->second.first) {
        shm_->destroy<IpcBuffer>(request->name().c_str());
      }

      std::lock_guard<std::mutex> lock(map_in_mutex_);
      streamin_map_.erase(it);

      return Status::OK;
    }

    Status Device_dump(ServerContext* context, const Empty* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      char *param = dev_->dump(dev_, 0);
      response->set_ret(param ? 0 : -1);
      response->set_status_string(std::string(param));

      // param is heap allocated and need free
      free(param);

      return Status::OK;
    }

    Status Device_set_master_mute(ServerContext* context, const Mute* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      response->set_ret(dev_->set_master_mute(dev_, request->mute()));
      return Status::OK;
    }

    Status Device_get_master_mute(ServerContext* context, const Empty* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      bool mute = false;
      response->set_ret(dev_->get_master_mute(dev_, &mute));
      response->set_status_bool(mute);
      return Status::OK;
    }

    Status Device_create_audio_patch(ServerContext* context, const CreateAudioPatch* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_port_config *sources, *sinks;
      unsigned int num_sources = request->sources_size();
      unsigned int num_sinks = request->sinks_size();

      struct audio_port_config *configs = new struct audio_port_config[num_sources + num_sinks];

      streamout_gc_();
      streamin_gc_();

      for (int i = 0; i < num_sources + num_sinks; i++) {
        const AudioPortConfig &config = (i < num_sources) ?
          request->sources(i) : request->sinks(i - num_sources);
        configs[i].id = config.id();
        configs[i].role = (audio_port_role_t)config.role();
        configs[i].type = (audio_port_type_t)config.type();
        configs[i].config_mask = config.config_mask();
        configs[i].sample_rate = config.sample_rate();
        configs[i].channel_mask = config.channel_mask();
        configs[i].format = (audio_format_t)config.format();

        // gain
        configs[i].gain.index = config.gain().index();
        configs[i].gain.mode = (audio_gain_mode_t)config.gain().mode();
        configs[i].gain.channel_mask = (audio_channel_mask_t)config.gain().channel_mask();
        for (int j = 0; j < config.gain().values_size(); j++)
          configs[i].gain.values[j] = config.gain().values(j);
        configs[i].gain.ramp_duration_ms = config.gain().ramp_duration_ms();

        if (configs[i].type == AUDIO_PORT_TYPE_DEVICE) {
          // AudioPortConfigDeviceExt
          configs[i].ext.device.hw_module = (audio_module_handle_t)config.device().hw_module();
          configs[i].ext.device.type = (audio_devices_t)config.device().type();
          strncpy(configs[i].ext.device.address, config.device().address().c_str(), AUDIO_DEVICE_MAX_ADDRESS_LEN);
        } else if (configs[i].type == AUDIO_PORT_TYPE_MIX) {
          // AudioPortConfigMixExt
          configs[i].ext.mix.hw_module = (audio_module_handle_t)config.mix().hw_module();
          configs[i].ext.mix.handle = (audio_io_handle_t)config.mix().handle();
          configs[i].ext.mix.usecase.stream = (audio_stream_type_t)config.mix().stream_source();
        } else if (configs[i].type == AUDIO_PORT_TYPE_SESSION) {
          // AudioPortConfigSessionExt
          configs[i].ext.session.session = (audio_session_t)config.session().session();
        }
      }

      audio_patch_handle_t handle = (audio_patch_handle_t)(-1);
      response->set_ret(dev_->create_audio_patch(dev_, num_sources,
                                                  configs, num_sinks, &configs[num_sources], &handle));
      response->set_status_32((uint32_t)handle);

      delete [] configs;

      return Status::OK;
    }

    Status Device_release_audio_patch(ServerContext* context, const Handle* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      audio_patch_handle_t handle = (audio_patch_handle_t)(request->handle());
      response->set_ret(dev_->release_audio_patch(dev_, handle));
      return Status::OK;
    }

    Status Device_set_audio_port_config(ServerContext* context, const AudioPortConfig* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_port_config config;

      config.id = request->id();
      config.role = (audio_port_role_t)request->role();
      config.type = (audio_port_type_t)request->type();
      config.config_mask = request->config_mask();
      config.sample_rate = request->sample_rate();
      config.channel_mask = request->channel_mask();
      config.format = (audio_format_t)request->format();

      // gain
      config.gain.index = request->gain().index();
      config.gain.mode = (audio_gain_mode_t)request->gain().mode();
      config.gain.channel_mask = (audio_channel_mask_t)request->gain().channel_mask();
      for (int j = 0; j < request->gain().values_size(); j++)
        config.gain.values[j] = request->gain().values(j);
      config.gain.ramp_duration_ms = request->gain().ramp_duration_ms();

      if (config.type == AUDIO_PORT_TYPE_DEVICE) {
        // AudioPortConfigDeviceExt
        config.ext.device.hw_module = (audio_module_handle_t)request->device().hw_module();
        config.ext.device.type = (audio_devices_t)request->device().type();
        strncpy(config.ext.device.address, request->device().address().c_str(), AUDIO_DEVICE_MAX_ADDRESS_LEN);
      } else if (config.type == AUDIO_PORT_TYPE_MIX) {
        // AudioPortConfigMixExt
        config.ext.mix.hw_module = (audio_module_handle_t)request->mix().hw_module();
        config.ext.mix.handle = (audio_io_handle_t)request->mix().handle();
        config.ext.mix.usecase.stream = (audio_stream_type_t)request->mix().stream_source();
      } else if (config.type == AUDIO_PORT_TYPE_SESSION) {
        // AudioPortConfigSessionExt
        config.ext.session.session = (audio_session_t)request->session().session();
      }

      response->set_ret(dev_->set_audio_port_config(dev_, &config));
      return Status::OK;
    }

    Status Stream_get_sample_rate(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->get_sample_rate(stream));
      return Status::OK;
    }

    Status Stream_get_buffer_size(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->get_buffer_size(stream));
      return Status::OK;
    }

    Status Stream_get_channels(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret((uint32_t)stream->get_channels(stream));
      return Status::OK;
    }

    Status Stream_get_format(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret((uint32_t)stream->get_format(stream));
      return Status::OK;
    }

    Status Stream_standby(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret((uint32_t)stream->standby(stream));
      return Status::OK;
    }

    Status Stream_get_device(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret((uint32_t)stream->get_device(stream));
      return Status::OK;
    }

    Status Stream_set_parameters(ServerContext* context, const StreamSetParameters* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      const char *kv_pairs = request->kv_pairs().c_str();
      response->set_ret(stream->set_parameters(stream, kv_pairs));
      return Status::OK;
    }

    Status Stream_get_parameters(ServerContext* context, const StreamGetParameters* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream *stream = find_stream(request->name(), streamout_map_, streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      char *param = stream->get_parameters(stream, request->keys().c_str());
      response->set_ret(param ? 0 : -1);
      response->set_status_string(std::string(param));

      // param is heap allocated and need free in behalf of client
      free(param);

      return Status::OK;
    }

    Status StreamOut_get_latency(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->get_latency(stream));
      return Status::OK;
    }

    Status StreamOut_set_volume(ServerContext* context, const StreamOutSetVolume* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->set_volume(stream, request->left(), request->right()));
      return Status::OK;
    }

    Status StreamOut_write(ServerContext* context, const StreamReadWrite* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      IpcBuffer *cb = shm_->find<IpcBuffer>(request->name().c_str()).first;
      response->set_ret(stream->write(stream, cb->start_ptr(), request->size()));
      return Status::OK;
    }

    Status StreamOut_get_render_position(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      uint32_t dsp_frames = 0;
      response->set_ret(stream->get_render_position(stream, &dsp_frames));
      response->set_status_32(dsp_frames);
      return Status::OK;
    }

    Status StreamOut_get_next_write_timestamp(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      int64_t timestamp = 0;
      response->set_ret(stream->get_next_write_timestamp(stream, &timestamp));
      response->set_status_64(timestamp);
      return Status::OK;
    }

    Status StreamOut_pause(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->pause(stream));
      return Status::OK;
    }

    Status StreamOut_resume(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->resume(stream));
      return Status::OK;
    }

    Status StreamOut_flush(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->flush(stream));
      return Status::OK;
    }

    Status StreamOut_get_presentation_position(ServerContext* context, const Stream* request, GetFrameTimestampReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_out *stream = find_streamout(request->name(), streamout_map_);
      if (stream == nullptr) return Status::CANCELLED;

      uint64_t frames = 0;
      struct timespec timestamp;
      response->set_ret(stream->get_presentation_position(stream, &frames, &timestamp));
      response->set_frames(frames);
      response->mutable_timestamp()->set_seconds((int64_t)timestamp.tv_sec);
      response->mutable_timestamp()->set_nanos(timestamp.tv_nsec);
      return Status::OK;
    }

    Status StreamIn_set_gain(ServerContext* context, const StreamGain* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_in *stream = find_streamin(request->name(), streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->set_gain(stream, request->gain()));
      return Status::OK;
    }

    Status StreamIn_read(ServerContext* context, const StreamReadWrite* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_in *stream = find_streamin(request->name(), streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      IpcBuffer *cb = shm_->find<IpcBuffer>(request->name().c_str()).first;
      response->set_ret(stream->read(stream, cb->start_ptr(), std::min((size_t) request->size(), cb->capacity())));
      return Status::OK;
    }

    Status StreamIn_get_input_frames_lost(ServerContext* context, const Stream* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_in *stream = find_streamin(request->name(), streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      response->set_ret(stream->get_input_frames_lost(stream));
      return Status::OK;
    }

    Status StreamIn_get_capture_position(ServerContext* context, const Stream* request, GetCapturePositionReturn* response) {
      TRACE_ENTRY();
      if (!dev_) return Status::CANCELLED;

      struct audio_stream_in *stream = find_streamin(request->name(), streamin_map_);
      if (stream == nullptr) return Status::CANCELLED;

      int64_t frames = 0;
      int64_t time = 0;
      response->set_ret(stream->get_capture_position(stream, &frames, &time));
      response->set_frames(frames);
      response->set_time(time);

      return Status::OK;
    }

    Status Service_ping(ServerContext* context, const Empty* empty, StatusReturn* response) {
      TRACE_ENTRY();
      response->set_status_32(0);
      return Status::OK;
    }

    Status Effect_set_parameters(ServerContext* context, const EffectParameters* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_ || !effect_) return Status::CANCELLED;

      aml_audio_effect_type_e type = (aml_audio_effect_type_e)request->type();
      uint32_t cmdSize = request->cmd_size();
      void *pCmdData = (void *)request->cmd_data().data();
      uint32_t replySize = request->reply_size();
      uint32_t pReplyData = 0;

      response->set_ret(effect_->set_parameters(type, cmdSize, pCmdData, &replySize, &pReplyData));
      response->set_status_32(pReplyData);
      return Status::OK;
    }

    Status Effect_get_parameters(ServerContext* context, const EffectParameters* request, StatusReturn* response) {
      TRACE_ENTRY();
      if (!dev_ || !effect_) return Status::CANCELLED;

      aml_audio_effect_type_e type = (aml_audio_effect_type_e)request->type();
      uint32_t cmdSize = request->cmd_size();
      void *pCmdData = (void *)request->cmd_data().data();
      uint32_t replySize = request->reply_size();
      void * pReplyData = malloc(replySize);

      response->set_ret(effect_->get_parameters(type, cmdSize, pCmdData, &replySize, pReplyData));
      response->set_status_bytes(pReplyData, replySize);
      free(pReplyData);
      pReplyData = nullptr;
      return Status::OK;
    }

  private:
    static int get_client_pid_(grpc::ServerContext* context)
    {
       ALOGI("peer %s", context->peer().c_str());

       // get the client socket fd
       int socketFd = -1;
       if ((sscanf(context->peer().c_str(), "fd:%d", &socketFd) != 1) || (socketFd < 0)) {
           ALOGE("Error: failed to get fd of the client");
           return -1;
       }

       // sanity check it's an actual fd by dup'ing it
       int duppedFd = fcntl(socketFd, F_DUPFD_CLOEXEC, 3);
       if (duppedFd < 0) {
         ALOGE("Error: failed to dup client socket fd (%d - %s)", errno, strerror(errno));
         return -1;
       }

       struct ucred cred;
       socklen_t credLen = sizeof(cred);
       if (getsockopt(duppedFd, SOL_SOCKET, SO_PEERCRED, &cred, &credLen) < 0) {
         ALOGE("Error: failed to get creds from client socket (%d - %s)", errno, strerror(errno));
         cred.pid = -1;
       }

       if (close(duppedFd) != 0) {
         ALOGE("Error: failed to close dup'd socket (%d - %s)", errno, strerror(errno));
       }

       return cred.pid;
    }


    void streamout_gc_()
    {
      std::lock_guard<std::mutex> lock_out(map_out_mutex_);
      for (std::map<const std::string, streamout_map_t >::iterator it = streamout_map_.begin(); it != streamout_map_.end(); ) {
          int pid, seq;
          bool need_close = false;

          if (sscanf(it->first.c_str(), "%d-%d", &pid, &seq) == 2) {
            // Garbage collect streams when PID does not exists.
            // It happens when client side crashed, or the client
            // side does not have the right sequence to close opened streams.
            if ((kill(pid, 0) == -1) && (errno == ESRCH)) {
              need_close = true;
            }
          }
          if (need_close) {
            ALOGI("Close disconnected output stream from PID %d", pid);
            dev_->close_output_stream(dev_, it->second.second);
            if (it->second.first) {
              shm_->destroy<IpcBuffer>(it->first.c_str());
            }
            streamout_map_.erase(it++);
          } else {
            ++it;
          }
      }
    }

    void streamin_gc_()
    {
      std::lock_guard<std::mutex> lock_out(map_in_mutex_);
      for (std::map<const std::string, streamin_map_t >::iterator it = streamin_map_.begin(); it != streamin_map_.end(); ) {
          int pid, seq;
          bool need_close = false;

          if (sscanf(it->first.c_str(), "%d-%d", &pid, &seq) == 2) {
            // Garbage collect streams when PID does not exists.
            // It happens when client side crashed, or the client
            // side does not have the right sequence to close opened streams.
            if (kill(pid, 0) == ESRCH) {
              need_close = true;
            }
          }
          if (need_close) {
            dev_->close_input_stream(dev_, it->second.second);
            streamin_map_.erase(it++);
          } else {
            ++it;
          }
      }
    }

    struct audio_stream *find_stream(std::string name,
                                     std::map<const std::string, streamout_map_t> &map_out,
                                     std::map<const std::string, streamin_map_t> &map_in)
    {
      std::lock_guard<std::mutex> lock_out(map_out_mutex_);
      std::map<const std::string, streamout_map_t >::iterator it_out = map_out.find(name);
      if (it_out != map_out.end()) {
        return &it_out->second.second->common;
      }

      std::lock_guard<std::mutex> lock_in(map_in_mutex_);
      std::map<const std::string, streamin_map_t >::iterator it_in = map_in.find(name);
      if (it_in != map_in.end()) {
        return &it_in->second.second->common;
      }

      return nullptr;
    }

    struct audio_stream_out *find_streamout(std::string name,
                                            std::map<const std::string, streamout_map_t> &map_out)
    {
      std::lock_guard<std::mutex> lock(map_out_mutex_);
      std::map<const std::string, streamout_map_t >::iterator it = map_out.find(name);
      if (it != map_out.end()) {
        return it->second.second;
      }

      return nullptr;
    }

    struct audio_stream_in *find_streamin(std::string name,
                                          std::map<const std::string, streamin_map_t> &map_in)
    {
      std::lock_guard<std::mutex> lock(map_in_mutex_);
      std::map<const std::string, streamin_map_t >::iterator it = map_in.find(name);
      if (it != map_in.end()) {
        return it->second.second;
      }

      return nullptr;
    }

    managed_shared_memory *shm_;

    /* audio hal interface */
    struct audio_hw_device *dev_;
    audio_effect_t *effect_;
    static std::mutex map_in_mutex_;
    static std::mutex map_out_mutex_;
    std::map<const std::string, streamout_map_t > streamout_map_;
    std::map<const std::string, streamin_map_t > streamin_map_;

    /* gc thread to close dead streams */
    bool gc_runner_stop_;
    std::mutex gc_mutex_;
    std::condition_variable gc_cv_;
    std::thread gc_runner_;
};

std::mutex AudioServiceImpl::map_out_mutex_;
std::mutex AudioServiceImpl::map_in_mutex_;

static void SetAudioPermissions(const char* file_path){
  struct stat buf;
  if (stat(file_path, &buf) != 0)
    return;

  chmod(file_path, (buf.st_mode & 0711) | 0066);
}

static bool runListenerLoop(const std::unique_ptr<grpc::Server> &server, const std::string &address)
{
  if (address.find("unix://") != 0) {
    ALOGE("Error: must be an 'unix://' server address");
    return false;
  }

  std::string socketPath = address.substr(strlen("unix://"));

  struct stat st;
  if ((stat(socketPath.c_str(), &st) == 0) && ((st.st_mode & S_IFMT) == S_IFSOCK)) {
    unlink(socketPath.c_str());
  }

  int serverSock = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (serverSock < 0) {
    ALOGE("Error: failed to create unix socket (%d - %s)", errno, strerror(errno));
    return false;
  }

  struct sockaddr_un serverAddr;
  memset(&serverAddr, 0, sizeof(serverAddr));
  serverAddr.sun_family = AF_UNIX;
  strncpy(serverAddr.sun_path, socketPath.c_str(), sizeof(serverAddr.sun_path) - 1);

  if (bind(serverSock, (struct sockaddr*)&serverAddr, sizeof(serverAddr)) != 0) {
    ALOGE("Error: failed to bind to unix socket @ '%s' (%d - %s)",
          socketPath.c_str(), errno, strerror(errno));
    return false;
  }

  SetAudioPermissions(socketPath.c_str());

  if (listen(serverSock, 5) == -1) {
    ALOGE("Error: failed to set socket to listening mode (%d - %s)",
          errno, strerror(errno));
    return false;
  }

  for (;;) {
    struct sockaddr_un clientAddr;
    socklen_t clientAddrLen = sizeof(clientAddr);
    int clientSock = TEMP_FAILURE_RETRY(accept4(serverSock,(struct sockaddr *) &clientAddr, &clientAddrLen, SOCK_NONBLOCK | SOCK_CLOEXEC));
    if (clientSock < 0) {
      ALOGE("Error: accepting new connection (%d - %s)", errno, strerror(errno));
      continue;
    }

    struct ucred cred;
    socklen_t credLen = sizeof(cred);
    if (getsockopt(clientSock, SOL_SOCKET, SO_PEERCRED, &cred, &credLen) < 0) {
      ALOGE("Error: failed to get creds from client socket (%d - %s)",
            errno, strerror(errno));
      close(clientSock);
      continue;
    }

    grpc::AddInsecureChannelFromFd(server.get(), clientSock);
  }

  return true;
}

void RunServer()
{
  const char *url = std::getenv("AUDIO_SERVER_SOCKET");
  std::string socket_location("/tmp/audio_socket");
  std::string server_address("unix://" + socket_location);
  AudioServiceImpl service;
  if (url) {
      server_address = url;
  }
  ServerBuilder builder;
  //builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
  builder.RegisterService(&service);
  std::unique_ptr<Server> server(builder.BuildAndStart());
  SetAudioPermissions(socket_location.c_str());
  SetAudioPermissions("/dev/shm/AudioServiceShmem");
  std::cout << "[AudioServer] listening on " << server_address << std::endl;
  runListenerLoop(server, server_address);
  server->Wait();
}

static int daemonize()
{
  int fd_pid;
  const char pidfile[] = "/var/run/audio_server.pid";
  char pid[10];

  fd_pid = open(pidfile, O_RDWR|O_CREAT, 0600);
  if (fd_pid == -1) {
    fprintf(stderr, "Unable to open PID lock file\n");
    return -1;
  }

  if (lockf(fd_pid, F_TLOCK, 0) == -1) {
    fprintf(stderr, "Unable to lock PID file, daemon is existing.\n");
    return -2;
  }

  snprintf(pid, sizeof(pid), "%d", getpid());
  write(fd_pid, pid, strlen(pid));

  return 0;
}

void handler(int sig)
{
  void *array[100];
  size_t size, i = 0;
  char ** trace;

  // get void*'s for all entries on the stack
  size = backtrace(array, 100);

  // print out all the frames to stderr
  fprintf(stderr, "Error: signal %d, size %d\n", sig, size);
  ALOGE("Error: signal %d, size %d", sig, size);
  trace = backtrace_symbols(array, size);

  if (trace) {
    for (i = 0; i < size; i++) {
      ALOGE("%s", trace[i]);
      fprintf(stderr, "%s\n", trace[i]);
    }
  } else {
    fprintf(stderr, "backtrace symbols error!!!\n");
    ALOGE("backtrace symbols error!!!");
  }

  exit(1);
}

int main(int argc, char** argv)
{
  int r = daemonize();
  if (r < 0)
    return r;

  //signal(SIGSEGV, handler);
  //signal(SIGABRT, handler);
  //signal(SIGFPE, handler);

  RunServer();
  return 0;
}
