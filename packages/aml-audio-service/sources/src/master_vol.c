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

#include <stdio.h>
#include <stdlib.h>
#include <audio_if.h>

static void usage()
{
    printf("Usage set volume             : master_vol s <volume: 0.0-1.0>\n");
    printf("      get volume             : master_vol g\n");
    printf("      set master mute/unmute : master_vol m <0, 1>\n");
}

int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    int ret;
    float vol;
    char cmd[256];

    if (argc < 2) {
        usage();
        return -1;
    }

    ret = audio_hw_load_interface(&device);
    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return ret;
    }

    ret = device->init_check(device);
    if (ret) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return -1;
    }

    if (argv[1][0] == 's') {
        if (argc < 3) {
            usage();
            return -1;
        }

        vol = atof(argv[2]);
        if ((vol < 0) || (vol > 1.0)) {
            printf("Volume must be between [0.0, 1.0]\n");
            audio_hw_unload_interface(device);
            return -1;
        }
        ret = device->set_master_volume(device, vol);
        printf("Volume %f set\n", vol);
    } else if (argv[1][0] == 'm') {
        if (argc < 3) {
            usage();
            return -1;
        }

        ret = device->set_master_mute(device, atoi(argv[2]) == 1);
    } else if (argv[1][0] == 'g') {
        ret = device->get_master_volume(device, &vol);
        if (ret == 0) {
            printf("Master volume: %f\n", vol);
        }
    } else {
        printf("Invalid command, use 's' or 'm' command.\n");
        ret = -2;
    }

    audio_hw_unload_interface(device);

    return ret;
}

