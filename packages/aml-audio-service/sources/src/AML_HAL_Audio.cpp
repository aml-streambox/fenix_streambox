/*
 * Copyright (C) 2023 Amlogic Corporation.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#include <string.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <audio_if.h>

#include "AML_HAL_Audio.h"
extern "C" {

#define DOLBY_MS12_LIB_PATH_A "/vendor/lib/libdolbyms12.so"
#define DOLBY_DCV_LIB_PATH_A "/usr/lib/libHwAudio_dcvdec.so"
#define DTS_DCA_LIB_PATH_A "/usr/lib/libHwAudio_dtshd.so"

#define DIGITAL_MODE_CMD "hdmi_format="
#define TRACK_MODE_CMD "sound_track="
#define AUDIO_SPDIF_MUTE_CMD "Audio spdif mute="
#define MS12_RUNTIME_CMD "ms12_runtime="

/** Dolby Lib Type used in Current System */
typedef enum eDolbyLibType {
    eDolbyNull  = 0,
    eDolbyDcvLib  = 1,
    eDolbyMS12Lib = 2,
} eDolbyLibType_t;

/*
 *@brief detect_dolby_lib_type
 */
static enum eDolbyLibType detect_dolby_lib_type(void) {
    enum eDolbyLibType retVal = eDolbyNull;

    void *hDolbyMS12LibHanle = NULL;
    void *hDolbyDcvLibHanle = NULL;

    // the priority would be "MS12 > DCV" lib
    if (access(DOLBY_MS12_LIB_PATH_A, R_OK) == 0) {
        retVal = eDolbyMS12Lib;
    }

    // MS12 is first priority
    if (eDolbyMS12Lib == retVal)
    {
        //try to open lib see if it's OK?
        hDolbyMS12LibHanle = dlopen(DOLBY_MS12_LIB_PATH_A, RTLD_NOW);
        if (hDolbyMS12LibHanle != NULL)
        {

            dlclose(hDolbyMS12LibHanle);
            hDolbyMS12LibHanle = NULL;
            printf("%s,FOUND libdolbyms12 lib\n", __FUNCTION__);
            return eDolbyMS12Lib;
        }
    }

    // dcv is second priority
    if (access(DOLBY_DCV_LIB_PATH_A, R_OK) == 0) {
        retVal = eDolbyDcvLib;
    } else {
        retVal = eDolbyNull;
    }

    if (eDolbyDcvLib == retVal)
    {
        //try to open lib see if it's OK?
        hDolbyDcvLibHanle  = dlopen(DOLBY_DCV_LIB_PATH_A, RTLD_NOW);
    }

    if (hDolbyDcvLibHanle != NULL)
    {
        dlclose(hDolbyDcvLibHanle);
        hDolbyDcvLibHanle = NULL;
        printf("%s,FOUND libHwAudio_dcvdec lib\n", __FUNCTION__);
        return eDolbyDcvLib;
    }

    printf("%s, failed to FIND libdolbyms12.so and libHwAudio_dcvdec.so, %s\n", __FUNCTION__, dlerror());
    return eDolbyNull;
}


static int dts_lib_decode_enable() {
    int enable = 0;
    unsigned int filesize = -1;
    struct stat stat_info = {0};

    if (stat(DTS_DCA_LIB_PATH_A, &stat_info) < 0) {
        enable = 0;
    } else {
        filesize = stat_info.st_size;
        if (filesize > 500*1024) {
            enable = 1;
        } else {
            enable = 0;
        }
    }

    return enable;
}

static int get_output_caps()
{
    int Capabilities=0;
    FILE *file = NULL;
    char  infobuf[260]={0};
    int32_t buf_len = 256;
    file = fopen("/sys/class/amhdmitx/amhdmitx0/aud_cap", "r");
    if (!file) {
        return 0;
    }
    fgets(infobuf, buf_len, file);
    while (NULL != fgets(infobuf, buf_len, file)) {
        printf("[AML] %s", infobuf);
        if (strstr(infobuf,"PCM,"))
            Capabilities |= AML_AUDIO_CAPS_PCM_MASK;
        if (strstr(infobuf,"AC-3,"))
            Capabilities |= AML_AUDIO_CAPS_DD_MASK;
        if (strstr(infobuf,"Dolby_Digital+,"))
            Capabilities |= AML_AUDIO_CAPS_DDP_MASK;
        if (strstr(infobuf,"Dolby_Digital+/ATMOS,"))
            Capabilities |= (AML_AUDIO_CAPS_ATMOS_MASK | AML_AUDIO_CAPS_DDP_MASK);
        if (strstr(infobuf,"MAT,"))
            Capabilities |= AML_AUDIO_CAPS_MAT_MASK;
        if (strstr(infobuf,"DTS,"))
            Capabilities |= AML_AUDIO_CAPS_DTS_MASK;
        if (strstr(infobuf,"DTS-HD,"))
            Capabilities |= AML_AUDIO_CAPS_DTSHD_MASK;

    }
    fclose(file);
    printf("[AML] Capabilities:0x%x\n", Capabilities);
    return Capabilities;
}

bool AML_HAL_Audio_Set_Volume (float vol)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    if ((vol < 0) || (vol > 1.0)) {
        printf("Volume must be between [0.0, 1.0]\n");
        return false;
    }
    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->set_master_volume(device,vol);
    if (ret) {
        printf("set master volume error\n");
        bret = false;
    }
    audio_hw_unload_interface(device);
    return bret;
}

float AML_HAL_Audio_Get_Volume()
{
    int ret;
    float vol = 0.0;
    audio_hw_device_t *device = NULL;
    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return 0.0;
    }
    ret = device->get_master_volume(device, &vol);
    if (ret) {
        printf("get master volume error\n");
    }
    printf("Master volume: %f\n", vol);
    audio_hw_unload_interface(device);
    return vol;
}

bool AML_HAL_Audio_Set_Mute(bool mute_flag)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->set_master_mute(device, mute_flag);
    if (ret) {
        fprintf(stderr, "set_master_mute error: %d\n", ret);
        bret = false;
    }
    audio_hw_unload_interface(device);
    return bret;
}

bool AML_HAL_Audio_Get_Mute()
{
    int ret;
    bool mute_state = false;
    audio_hw_device_t *device = NULL;
    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return false;
    }
    ret = device->get_master_mute(device, &mute_state);
    if (ret) {
        printf("adev_get_master_mute: %d\n", ret);
    }

    audio_hw_unload_interface(device);
    return mute_state;
}

bool AML_HAL_Audio_Set_Spdif_Mute(bool mute_flag)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    char cmd[256] = {0};

    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->init_check(device);
    if (ret) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return false;
    }

    snprintf(cmd, sizeof(cmd), "%s%d", AUDIO_SPDIF_MUTE_CMD, mute_flag);
    ret = device->set_parameters(device, cmd);
    if (ret) {
        fprintf(stderr, "device->set_parameters: %d\n", ret);
        bret = false;
    }

    audio_hw_unload_interface(device);
    return bret;
}

bool AML_HAL_Audio_Set_Output_Mode(enum digital_format mode)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    char cmd[256] = {0};

    if ((mode != AML_HAL_PCM) &&
        (mode != AML_HAL_DD) &&
        (mode != AML_HAL_Auto) &&
        (mode != AML_HAL_Bypass)) {
        printf("Invalid mode\n");
        return false;
    }

    ret = audio_hw_load_interface(&device);
    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->init_check(device);
    if (ret) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return false;
    }

    snprintf(cmd, sizeof(cmd), "%s%d", DIGITAL_MODE_CMD, mode);
    ret = device->set_parameters(device, cmd);
    if (ret) {
        fprintf(stderr, "device->set_parameters: %d\n", ret);
        bret = false;
    }

    audio_hw_unload_interface(device);
    return bret;
}

bool AML_HAL_Audio_Set_Track_Mode(enum AML_Audio_TrackMode mode)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    char cmd[256] = {0};

    if ((mode < AML_AUDIO_TRACKMODE_STEREO) ||
        (mode > AML_AUDIO_TRACKMODE_MIX)) {
        printf("Invalid mode\n");
        return false;
    }

    ret = audio_hw_load_interface(&device);
    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->init_check(device);
    if (ret) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return false;
    }

    snprintf(cmd, sizeof(cmd), "%s%d", TRACK_MODE_CMD, mode);
    ret = device->set_parameters(device, cmd);
    if (ret) {
        fprintf(stderr, "device->set_parameters: %d\n", ret);
        bret = false;
    }

    audio_hw_unload_interface(device);
    return bret;
}

enum digital_format AML_HAL_Audio_Get_Output_Mode()
{
    enum digital_format ret = AML_HAL_ERROR;
    audio_hw_device_t *device = NULL;
    char * param = NULL;

    if (audio_hw_load_interface(&device)) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return AML_HAL_ERROR;
    }

    param = device->get_parameters(device,"hdmi_format");

    if (param) {
        printf("%s\n", param);
        switch (param[12]) {
        case '0':
            printf("%s:AML_HAL_PCM\n",__func__);
            ret = AML_HAL_PCM;
            break;
        case '4':
            printf("%s:AML_HAL_DD\n",__func__);
            ret = AML_HAL_DD;
            break;
        case '5':
            printf("%s:AML_HAL_Auto\n",__func__);
            ret = AML_HAL_Auto;
            break;
        case '6':
            printf("%s:AML_HAL_Bypass\n",__func__);
            ret = AML_HAL_Bypass;
            break;
        default :
            printf("%s:AML_HAL_ERROR\n",__func__);
            ret = AML_HAL_ERROR;
            break;
        }
        free(param);
    }

    audio_hw_unload_interface(device);

    if (ret == AML_HAL_Auto) {
        //MAT > DDP > DD > PCM
        ret = AML_HAL_PCM;
        int caps = get_output_caps();
        if ((caps & AML_AUDIO_CAPS_MAT_MASK) == AML_AUDIO_CAPS_MAT_MASK) {
            ret = AML_HAL_MAT;
        } else if ((caps & AML_AUDIO_CAPS_DDP_MASK) == AML_AUDIO_CAPS_DDP_MASK) {
            ret = AML_HAL_DDP;
        } else if ((caps & AML_AUDIO_CAPS_DD_MASK) == AML_AUDIO_CAPS_DD_MASK) {
            ret = AML_HAL_DD;
        }
    }

    return ret;
}

enum AML_DecodeType AML_HAL_Audio_Get_Decode_Type ( enum AML_Audio_Src_Format format)
{
    enum eDolbyLibType dolbylibtype = eDolbyNull;
    int dtshd_enbale = 0;
    dolbylibtype = detect_dolby_lib_type();
    dtshd_enbale = dts_lib_decode_enable();
    enum AML_DecodeType ret = AML_INVALIAD;
    switch (format) {
        case AML_AUDIO_FORMAT_AC3 :
        case AML_AUDIO_FORMAT_E_AC3 :
            if (dolbylibtype == 2)
                ret = AML_MS12;
            else if (dolbylibtype == 1)
                ret = AML_DolbyDCV;
            break;
        case AML_AUDIO_FORMAT_AC4 :
        case AML_AUDIO_FORMAT_DOLBY_TRUEHD:
        case AML_AUDIO_FORMAT_MAT:
            if (dolbylibtype == 2)
                ret = AML_MS12;
            break;
        case AML_AUDIO_FORMAT_DTS:
        case AML_AUDIO_FORMAT_DTS_HD:
            if (dtshd_enbale)
                ret = AML_DTSHD;
            break;
        default:
            break;
    }
    return ret;
}

int AML_HAL_Audio_Capabilities_Get()
{
    return get_output_caps();
}

bool AML_HAL_Audio_Set_AC4_Dialog_Enhancer(int ac4_de)
{
    int ret;
    bool bret = true;
    audio_hw_device_t *device = NULL;
    char cmd[256] = {0};

    ret = audio_hw_load_interface(&device);
    if (ret) {
        printf("audio_hw_load_interface failed: %d\n", ret);
        return false;
    }

    ret = device->init_check(device);
    if (ret) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return false;
    }

    snprintf(cmd, sizeof(cmd), "%s%s %d", MS12_RUNTIME_CMD, "-ac4_de", ac4_de);
    ret = device->set_parameters(device, cmd);
    if (ret) {
        fprintf(stderr, "device->set_parameters: %d\n", ret);
        bret = false;
    }

    audio_hw_unload_interface(device);
    return bret;
}

}//extern c
