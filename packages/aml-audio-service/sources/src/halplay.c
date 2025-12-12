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
#include "audio_if.h"
#include <signal.h>

#define min(a, b) ((a) < (b) ? (a) : (b))
#define WRITE_UNIT 4096

enum audio_format {
    FORMAT_PCM16 = 0,
    FORMAT_PCM32,
    FORMAT_DD,
    FORMAT_MAT,
    FORMAT_IEC61937,
    FORMAT_AC4 = 5,
    FORMAT_MP3,
    FORMAT_AAC,
    FORMAT_OGG,
    FORMAT_FLAC,
    FORMAT_TRUE_HD,
    FORMAT_MAX
};

static int format_tab[] = {
    AUDIO_FORMAT_PCM_16_BIT,
    AUDIO_FORMAT_PCM_32_BIT,
    AUDIO_FORMAT_AC3,
    AUDIO_FORMAT_MAT,
    AUDIO_FORMAT_IEC61937,
    AUDIO_FORMAT_AC4,
    AUDIO_FORMAT_MP3,
    AUDIO_FORMAT_AAC,
    AUDIO_FORMAT_VORBIS,
    AUDIO_FORMAT_FLAC,
    AUDIO_FORMAT_DOLBY_TRUEHD
};

static const char *format_str[] = {
    "PCM_16",
    "PCM_32",
    "DOLBY DD/DD+",
    "DOLBY MAT",
    "IEC_61937",
    "AC4",
    "MP3",
    "AAC",
    "OGG",
    "FLAC",
    "TRUE_HD"
};

static int format_is_pcm(int format)
{
    return (format == FORMAT_PCM16) || (format == FORMAT_PCM32);
}

static unsigned char *fmap(const char *fn, int *size, int *fd)
{
    int fd_r, r;
    struct stat st;
    unsigned char *p;

    fd_r = open(fn, O_RDWR);

    if (fd_r < 0)
        return NULL;

    *fd = fd_r;
    r = fstat(fd_r, &st);
    *size = st.st_size;
    return mmap(0, st.st_size, PROT_READ|PROT_EXEC, MAP_SHARED, fd_r, 0);
}

static void funmap(unsigned char *p, int size, int fd)
{
    if (p && size > 0)
        munmap(p, size);
    if (fd >= 0)
        close(fd);
}

int debug = 0;
static void get_buffer_size(struct audio_stream_out *stream)
{
    int buffer_size = 0;
    int buffer_latency = 0;
    if (debug) {
        buffer_size = stream->common.get_buffer_size(&(stream->common));
        buffer_latency = stream->get_latency(stream);
        printf("buffer_size: %d, buffer_latency: %d.", buffer_size, buffer_latency);
    }
}

int isstop = 0;
static int test_stream(struct audio_stream_out *stream, unsigned char *buf, int size)
{
    int ret;
    int len = size;
    unsigned char *data = buf;

    ret = stream->common.standby(&stream->common);
    if (ret) {
        fprintf(stderr, "%s %d, ret:%x\n",
                __func__, __LINE__, ret);
        return -1;
    }

    ret = stream->set_volume(stream, 1.0f, 1.0f);
    if (ret) {
        fprintf(stderr, "%s %d, ret:%x\n", __func__, __LINE__, ret);
        return -1;
    }

    while (len > 0) {
        ssize_t s = stream->write(stream, data, min(len, WRITE_UNIT));
        if (s < 0) {
            fprintf(stderr, "stream writing error %d\n", s);
            break;
        }
        if (isstop) {
            break;
        }
        printf("stream writing %d \n", s);
        len -= s;
        data += s;

        get_buffer_size(stream);
    }
    isstop = 0;
    return 0;
}

static void test_output_stream(audio_hw_device_t *device, unsigned char *buf, int size, struct audio_config *config)
{
    struct audio_stream_out *stream;
    int ret;

    printf("open output speaker...\n");
    ret = device->open_output_stream(device,
            0, AUDIO_DEVICE_OUT_SPEAKER,
            AUDIO_OUTPUT_FLAG_PRIMARY, config,
            &stream, NULL);
    if (ret) {
        printf("fail\n");
        return;
    } else {
        printf("success\n");
    }

    test_stream(stream, buf, size);

    printf("close output speaker...\n");
    device->close_output_stream(device, stream);
}
void handler_halplay(int sig)
{
    isstop=1;
    while (isstop != 1);
    printf("\n handler_halplay...\n");
}
int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    int ret, c = -1, format = FORMAT_MAX, ch = 0, sr = 0, help = 0;
    struct audio_config config;
    const char *fn = NULL;
    int size = 0;
    unsigned char *buf;
    int fd = -1;

    if (argc == 1) {
        printf("Usage: halplay -f <format> -c <channel number> -r <sample rate> -d <debug flag> <filename> \n");
        printf("more param Info: halplay -h\n");
        return 0;
    }

    while ((c = getopt(argc, argv, "f:c:r:d:h")) != -1) {
        switch (c) {
            case 'f':
                format = atoi(optarg);
                break;
            case 'c':
                ch = atoi(optarg);
                break;
            case 'r':
                sr = atoi(optarg);
                break;
            case 'd':
                debug = atoi(optarg);
                break;
            case 'h':
                help = 1;
                break;
            case '?':
                fprintf(stderr, "Error in an argument.\n");
                return -1;
            default:
                return -1;
        }
    }
    if (help == 1) {
        printf("Usage: halplay -f <format> -c <channel number> -r <sample rate> -d <debug flag> <filename>\n");
        printf("\n-h,           help\n");
        printf("-f,           sample format\n");
        printf("-c,           channels\n");
        printf("-r,           sample rate\n");
        printf("Recognized sample formats are: 0:PCM16 1:PCM32 2:DD 3:MAT 4:IEC61937 5:AC4 6:MP3 7:AAC 8:OGG 9:FLAC 10:true-hd\n");
        printf("Some of these may not be available on selected format\n");
        printf("the available params for PCM16 and PCM32 are:\n");
        printf("-c 1,2,6,8\n");
        printf("-r 32000,44100,48000\n");
        printf("-d debug flag: 1/0\n");
        return 0;
    }
    if (optind < argc) {
        fn = argv[optind];
    }

    if (!fn) {
        fprintf(stderr, "No file name specified\n");
        return -1;
    }

    if ((format < 0) || (format >= FORMAT_MAX)) {
        int i;
        fprintf(stderr, "Wrong format, valid format:\n");
        for (i = 0; i < FORMAT_MAX; i++)
            fprintf(stderr, "\t%d: %s\n", i, format_str[i]);
        return -1;
    }

    if (format_is_pcm(format)) {
        if ((ch < 1) || (ch > 8)) {
            fprintf(stderr, "Wrong channel number, valid range [1-8]\n");
            return -1;
        }
        if ((sr != 32000) && (sr != 44100) && (sr != 48000)) {
            fprintf(stderr, "Invalid sample rate, valid options [32000, 44100, 48000]\n");
            return -1;
        }
        if ((ch != 1) && (ch != 2) && (ch != 6) && (ch != 8)) {
            fprintf(stderr, "Invalid channel number, valid options [1, 2, 6, 8]\n");
            return -1;
        }
    }

    ret = audio_hw_load_interface(&device);
    if (ret) {
        fprintf(stderr, "%s %d error:%d\n", __func__, __LINE__, ret);
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

    buf = fmap(fn, &size, &fd);
    if (!buf) {
        fprintf(stderr, "Error, cannot open input file\n");
        goto exit;
    }

    /* set audio config */
    memset(&config, 0, sizeof(config));

    switch (format) {
        case FORMAT_PCM16:
        case FORMAT_PCM32:
            config.sample_rate = sr;
            switch (ch) {
                case 1:
                    config.channel_mask = AUDIO_CHANNEL_OUT_MONO;
                    break;
                case 2:
                    config.channel_mask = AUDIO_CHANNEL_OUT_STEREO;
                    break;
                case 6:
                    config.channel_mask = AUDIO_CHANNEL_OUT_5POINT1;
                    break;
                case 8:
                    config.channel_mask = AUDIO_CHANNEL_OUT_7POINT1;
                    break;
                default:
                    config.channel_mask = AUDIO_CHANNEL_OUT_STEREO;
                    break;
            }
            break;

        case FORMAT_DD:
        case FORMAT_MAT:
        case FORMAT_IEC61937:
        case FORMAT_AC4:
            config.sample_rate = 48000;
            config.channel_mask = AUDIO_CHANNEL_OUT_5POINT1;
            break;

        case FORMAT_MP3:
        case FORMAT_AAC:
        case FORMAT_OGG:
        case FORMAT_FLAC:
            config.sample_rate = sr;
            config.channel_mask = AUDIO_CHANNEL_OUT_STEREO;
            break;
        case FORMAT_TRUE_HD:
            config.sample_rate = sr;
            switch (ch) {
                case 8:
                    config.channel_mask = AUDIO_CHANNEL_OUT_7POINT1;
                    break;
                default:
                    config.channel_mask = AUDIO_CHANNEL_OUT_STEREO;
                    break;
            }
            break;

        default:
            break;
    }

    config.format = format_tab[format];
    signal(SIGINT, handler_halplay);
    test_output_stream(device, buf, size, &config);

    funmap(buf, size, fd);

exit:
    audio_hw_unload_interface(device);
    return 0;
}
