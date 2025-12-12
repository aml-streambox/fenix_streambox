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


#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include "ac3data.h"
#include "audio_if.h"

#define min(a, b) ((a) < (b) ? (a) : (b))
#define WRITE_UNIT 1536

static int test_stream(struct audio_stream_out *stream)
{
    int ret;
    int len;
    const unsigned char *data;
    printf("%s %d, ch_mask:%x\n",
            __func__, __LINE__,
            stream->common.get_channels(&stream->common));
    printf("%s %d, format:%x\n",
            __func__, __LINE__,
            stream->common.get_format(&stream->common));
    printf("%s %d, sr:%d\n",
            __func__, __LINE__,
            stream->common.get_sample_rate(&stream->common));
    ret = stream->common.standby(&stream->common);
    if (ret) {
        printf("%s %d, ret:%x\n",
                __func__, __LINE__, ret);
        return -1;
    }

    ret = stream->set_volume(stream, 1.0f, 1.0f);
    if (ret) {
        printf("%s %d, ret:%x\n", __func__, __LINE__, ret);
        return -1;
    }

    data = ac3_dat;
    len = sizeof(ac3_dat);
    while (len > 0) {
        ssize_t s = stream->write(stream, data, min(len, WRITE_UNIT));
        if (s < 0) {
            printf("stream writing error %d\n", s);
            break;
        }

        len -= s;
        data += s;
    }

    uint32_t latency = stream->get_latency(stream);
    printf("%s %d, write %d latency\n", __func__, __LINE__, latency);

    int pos = 0;
    ret = stream->get_render_position(stream, &pos);
    if (ret) {
        printf("%s %d, ret:%x\n", __func__, __LINE__, ret);
        return -1;
    }
    printf("%s %d, pos:%d\n", __func__, __LINE__, pos);
    return 0;
}

static void test_output_stream(audio_hw_device_t *device)
{
    int ret;
    struct audio_config config;
    struct audio_stream_out *stream;

    memset(&config, 0, sizeof(config));
    config.sample_rate = 48000;
    config.channel_mask = AUDIO_CHANNEL_OUT_5POINT1;
    config.format = AUDIO_FORMAT_AC3;

    printf("open output speaker...\n");
    ret = device->open_output_stream(device,
            0, AUDIO_DEVICE_OUT_SPEAKER,
            AUDIO_OUTPUT_FLAG_PRIMARY, &config,
            &stream, NULL);
    if (ret) {
        printf("fail\n");
        return;
    } else {
        printf("success\n");
    }
    test_stream(stream);
    printf("close output speaker...\n");
    device->close_output_stream(device, stream);
}

int main()
{
    int ret;
    audio_hw_device_t *device;

    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("%s %d error:%d\n", __func__, __LINE__, ret);
        return ret;
    }
    printf("hw version: %x\n", device->common.version);
    printf("hal api version: %x\n", device->common.module->hal_api_version);
    printf("module id: %s\n", device->common.module->id);
    printf("module name: %s\n", device->common.module->name);

    if (device->get_supported_devices) {
        uint32_t support_dev = 0;
        support_dev = device->get_supported_devices(device);
        printf("supported device: %x\n", support_dev);
    }

    int inited = device->init_check(device);
    if (inited) {
        printf("device not inited, quit\n");
        goto exit;
    }

    test_output_stream(device);

exit:
    audio_hw_unload_interface(device);
    return 0;
}
