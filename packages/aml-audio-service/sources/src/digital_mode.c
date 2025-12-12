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

#define DIGITAL_MODE_PCM    0
#define DIGITAL_MODE_DD     4
#define DIGITAL_MODE_AUTO   5
#define DIGITAL_MODE_BYPASS 6

#define DIGITAL_MODE_CMD "hdmi_format="

int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    int mode, ret;
    char cmd[256];

    if (argc < 2) {
        printf("Usage: digital_mode <mode>\n");
        return -1;
    }

    mode = atoi(argv[1]);
    if ((mode != DIGITAL_MODE_PCM) &&
        (mode != DIGITAL_MODE_DD) &&
        (mode != DIGITAL_MODE_AUTO) &&
        (mode != DIGITAL_MODE_BYPASS)) {
        printf("Invalid mode\n");
        return -2;
    }
    snprintf(cmd, sizeof(cmd), "%s%d", DIGITAL_MODE_CMD, mode);

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

    ret = device->set_parameters(device, cmd);
    printf("set_parameters returns %d\n", ret);

    audio_hw_unload_interface(device);

    return ret;
}

