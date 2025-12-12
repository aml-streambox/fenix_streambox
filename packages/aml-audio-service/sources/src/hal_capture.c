/*
 * Copyright (C) 2021 Amlogic Corporation.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include "audio_if.h"

#define AML_FRAME_SIZE 256

int quit_flag = 0;
int in_device = 0;
audio_hw_device_t *device;
struct audio_stream_in *stream;

enum capture_format {
    FORMAT_PCM_16_BIT = 0,
    FORMAT_PCM_32_BIT,
    FORMAT_MAX
};

enum capture_device {
    DEVICE_TDM = 0,
    DEVICE_PDM,
    DEVICE_AEC,
    DEVICE_MAX
};

static const char *format_str[] = {
    "PCM_16_LE",
    "PCM_32_LE",
};

static const char *device_str[] = {
    "TDM",
    "PDM",
    "AEC"
};

static unsigned int channel_mask_to_num(audio_channel_mask_t channel_mask)
{
    int ret = 0;
    switch (channel_mask) {
        case AUDIO_CHANNEL_IN_MONO:
            ret = 1;
            break;
        case AUDIO_CHANNEL_IN_STEREO:
            ret = 2;
            break;
        case AUDIO_CHANNEL_IN_2POINT0POINT2:
            ret = 4;
            break;
        default:
            printf("Wrong channel mask: %x!!!\n", channel_mask);
            return 0;
    }
    return ret;
}

static unsigned int pcm_format_to_bits(enum capture_format format)
{
    switch (format) {
        case AUDIO_FORMAT_PCM_16_BIT:
            return 16;
        case AUDIO_FORMAT_PCM_32_BIT:
            return 32;
        default:
            printf("Wrong pcm format!!!\n");
            return 0;
    };
}


void handler(int sig)
{
    quit_flag = 1;
}

void capture_read_input_stream(struct audio_config *config)
{
    int ret = 0;
    int read_len = 0;
    int flen = 0;
    char *buffer = NULL;
    int buffer_size = AML_FRAME_SIZE * channel_mask_to_num(config->channel_mask)
                      * (pcm_format_to_bits(config->format) >> 3);

    buffer = (char *)calloc(1, buffer_size * sizeof(char));
    FILE *fp = fopen("/data/hal_capture.raw", "r");
    if (fp != NULL) {
        fclose(fp);
        remove("/data/hal_capture.raw");
    }

    fp = fopen("/data/hal_capture.raw", "a+");
    if (fp) {
        while (!quit_flag) {
            ret = stream->read(stream, buffer, buffer_size);
            read_len += (ret/1024);
            flen = fwrite((char *)buffer, 1, buffer_size, fp);
            memset(buffer, 0, buffer_size);
        }

        printf("Capture data:%d k\n", read_len);
        free(buffer);
        buffer = NULL;
        fclose(fp);
    }

    return;
}

void capture_open_input_stream(struct audio_config *config)
{
    int ret = 0;

    printf("open input stream...\n");

    ret = device->open_input_stream(device, 0, in_device, config, &stream, AUDIO_INPUT_FLAG_RAW, NULL, AUDIO_SOURCE_MIC);
    if (ret) {
        printf("open input stream fail\n");
    } else {
        printf("open input stream success\n");
    }

    return;
}

void capture_close_input_stream()
{
    printf("close input stream...\n");
    device->close_input_stream(device, stream);
    return;
}

int capture_parse_options(int argc, char **argv, struct audio_config *config)
{
    int i = 0;
    int c = -1;

    if (argc == 1) {
        printf("Usage: hal_capture -d <device> -f <format> -c <channel number> -r <sample rate>\n");
        for (i = 0; i < FORMAT_MAX; i++) {
            printf("format:\t%d: %s\n", i, format_str[i]);
        }

        for (i = 0; i < DEVICE_MAX; i++) {
            printf("device:\t%d: %s\n", i, device_str[i]);
        }
        return -1;
    }

    memset(config, 0, sizeof(struct audio_config));
    while ((c = getopt(argc, argv, "d:f:c:r:")) != -1) {
        switch (c) {
            case 'd':
                in_device = atoi(optarg);
                break;
            case 'f':
                config->format = atoi(optarg);
                break;
            case 'c':
                config->channel_mask = atoi(optarg);
                break;
            case 'r':
                config->sample_rate = atoi(optarg);
                break;
            case '?':
                fprintf(stderr, "Error in an argument.\n");
                return -1;
            default:
                return -1;
        }
    }

    switch (in_device) {
        case DEVICE_TDM:
            in_device = AUDIO_DEVICE_IN_WIRED_HEADSET;
            break;
        case DEVICE_PDM:
            in_device = AUDIO_DEVICE_IN_BUILTIN_MIC;
            break;
        case DEVICE_AEC:
            in_device = AUDIO_DEVICE_IN_ECHO_REFERENCE;
            break;
        default:
            printf("Wrong device, valid format:\n");
            return -1;
    }

    switch (config->format) {
        case FORMAT_PCM_16_BIT:
            config->format = AUDIO_FORMAT_PCM_16_BIT;
            break;
        case FORMAT_PCM_32_BIT:
            config->format = AUDIO_FORMAT_PCM_32_BIT;
            break;
        default:
            printf("Wrong format, valid format:%d\n", config->format);
            return -1;
    }

    switch (config->channel_mask) {
        case 1:
            config->channel_mask = AUDIO_CHANNEL_IN_MONO;
            break;
        case 2:
            config->channel_mask = AUDIO_CHANNEL_IN_STEREO;
            break;
        default:
            printf("Wrong channel number, valid range [1~2], channel_mask:%x\n", config->channel_mask);
            return -1;
    }

    switch (config->sample_rate) {
        case 8000:
        case 11025:
        case 12000:
        case 16000:
        case 17000:
        case 22050:
        case 24000:
        case 32000:
        case 44100:
        case 48000:
        case 96000:
            break;
        default:
            printf("Unsupported (%d) samplerate passed", config->sample_rate);
            return -1;
    }

    return 0;
}

int main(int argc, char *argv[])
{
    int ret = 0;
    unsigned int support_dev = 0;
    int inited = 0;
    struct audio_config config;

    ret = capture_parse_options(argc, argv, &config);
    if (ret == -1) {
        printf("Option error, please check the parameters\n");
        return ret;
    }

    /* Register interrupt handling callback */
    signal(SIGINT, handler);

    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("Load hw interface error:%d\n", ret);
        return ret;
    }

    printf("hw version: %x\n", device->common.version);
    printf("hal api version: %x\n", device->common.module->hal_api_version);
    printf("module id: %s\n", device->common.module->id);
    printf("module name: %s\n", device->common.module->name);

    if (device->get_supported_devices) {
        support_dev = device->get_supported_devices(device);
        printf("supported device: %x\n", support_dev);
    }

    inited = device->init_check(device);
    if (inited != 0) {
        printf("device not inited, quit\n");
        goto exit;
    }

    capture_open_input_stream(&config);
    capture_read_input_stream(&config);
    capture_close_input_stream();

exit:
    audio_hw_unload_interface(device);
    return 0;
}
