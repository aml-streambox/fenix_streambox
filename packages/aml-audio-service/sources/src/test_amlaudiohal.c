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
#include <stdio.h>
#include <stdlib.h>

#include <AML_HAL_Audio.h>

static void usage()
{
    printf("Usage set volume             : test_amlhalaudio vol_s <volume: 0.0-1.0>\n");
    printf("      get volume             : test_amlhalaudio vol_g\n");
    printf("      set mute status        : test_amlhalaudio m_s <0, 1>\n");
    printf("      get mute status        : test_amlhalaudio m_g \n");
    printf("      set output mode        : test_amlhalaudio outmode_s x <PCM:0, DD: 4, Auto: 5, bypass: 6>\n");
    printf("      get output mode        : test_amlhalaudio outmode_g \n");
    printf("      get decoder type       : test_amlhalaudio decoder x <AC3:0, EAC3:1, AC4:2, TrueHD:3, MAT:4, DTS:5, DTSHD:6>\n");
    printf("      get caps               : test_amlhalaudio caps \n");
    printf("      set track mode         : test_amlhalaudio trackmode x <Stereo:0, DUAL_LEFT: 1, DUAL_RIGHT: 2, SWAP : 3, MIX : 4> \n");
}

int main(int argc, char **argv)
{
    float vol;
    int ret;
    if (argc < 2) {
        usage();
        return -1;
    }
    if (!strncmp("vol_s", argv[1], sizeof("vol_s"))) {
        vol = atof(argv[2]);
        AML_HAL_Audio_Set_Volume(vol);
    } else if (!strncmp("vol_g", argv[1], sizeof("vol_g"))) {
        vol = AML_HAL_Audio_Get_Volume();
        printf("Audio_Get_Volume success:vol =%f\n",vol);
    } else if (!strncmp("m_s", argv[1], sizeof("m_s"))) {
        ret = atoi(argv[2]);
        AML_HAL_Audio_Set_Mute(ret);
    } else if (!strncmp("m_g", argv[1], sizeof("m_g"))) {
        printf("Audio mute state:%d\n", AML_HAL_Audio_Get_Mute());
    } else if (!strncmp("outmode_s", argv[1], sizeof("outmode_s"))) {
        ret = atoi(argv[2]);
        printf("dig_mode_set:mode=%d\n",ret);
        AML_HAL_Audio_Set_Output_Mode(ret);
    } else if (!strncmp("outmode_g", argv[1], sizeof("outmode_g"))) {
        printf("output mode = %d\n", AML_HAL_Audio_Get_Output_Mode());
    } else if (!strncmp("decoder", argv[1], sizeof("decoder"))) {
        ret = atoi(argv[2]);
        printf("AML_decode_type=%d\n", AML_HAL_Audio_Get_Decode_Type(ret));
    } else if (!strncmp("caps", argv[1], sizeof("caps"))) {
        printf("Capability=0x%x\n", AML_HAL_Audio_Capabilities_Get());
    } else if (!strncmp("trackmode", argv[1], sizeof("trackmode"))) {
        ret = atoi(argv[2]);
        printf("track_mode_set:mode=%d\n",ret);
        AML_HAL_Audio_Set_Track_Mode(ret);
    }
    return 0;
}

