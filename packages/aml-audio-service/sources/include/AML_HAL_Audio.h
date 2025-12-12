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


#ifndef __AML_HAL_AUDIO_H__
#define __AML_HAL_AUDIO_H__

#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif


enum digital_format {
    AML_HAL_ERROR = -1, //output format is ERROR
    AML_HAL_PCM = 0,    //output format is PCM
    AML_HAL_DD = 4,     //output format is DD
    AML_HAL_Auto,       //output format is Auto and depends on the HDMI output device’s capability
    AML_HAL_Bypass,     //output format is Bypass
    AML_HAL_DDP,
    AML_HAL_MAT,
};

/**\brief Audio output mode*/
enum AML_Audio_TrackMode {
    AML_AUDIO_TRACKMODE_STEREO,     /**< Stereo output*/
    AML_AUDIO_TRACKMODE_DUAL_LEFT,  /**< Left audio output to dual channel*/
    AML_AUDIO_TRACKMODE_DUAL_RIGHT, /**< Right audio output to dual channel*/
    AML_AUDIO_TRACKMODE_SWAP,       /**< Swap left and right channel*/
    AML_AUDIO_TRACKMODE_MIX,        /**< Mix*/
};

enum AML_Audio_Src_Format {
   AML_AUDIO_FORMAT_AC3,
   AML_AUDIO_FORMAT_E_AC3,
   AML_AUDIO_FORMAT_AC4,
   AML_AUDIO_FORMAT_DOLBY_TRUEHD,
   AML_AUDIO_FORMAT_MAT,
   AML_AUDIO_FORMAT_DTS,
   AML_AUDIO_FORMAT_DTS_HD,
};

enum AML_Audio_Caps_Mask {
    AML_AUDIO_CAPS_PCM_MASK = 0x1 << 0,
    AML_AUDIO_CAPS_DD_MASK = 0x1 << 1,
    AML_AUDIO_CAPS_DDP_MASK = 0x1 << 2,
    AML_AUDIO_CAPS_ATMOS_MASK = 0x1 << 3,
    AML_AUDIO_CAPS_MAT_MASK = 0x1 << 4,
    AML_AUDIO_CAPS_DTS_MASK = 0x1 << 5,
    AML_AUDIO_CAPS_DTSHD_MASK = 0x1 << 6,
};

enum AML_DecodeType {
   AML_DolbyDCV,   //Support decoding format AC3/EAC3.
   AML_MS12,       //Support decoding format ATMOS/AC4/TRUEHD.
   AML_DTS,        //Support decoding format DTS core only
   AML_DTSHD,      //Support decoding format DTS/DTS_HD
   AML_INVALIAD,   //there is no decoding type supports this audio format
};

/*
*@brief     set volume
*@param     Set volume value,The range of the value is [0,1],value is a float type
*@return    Return bool type value,TRUE is setting successful and FALSE is setting failed
*/
bool AML_HAL_Audio_Set_Volume (float vol);

/**
*@brief     This API is used to get volume
*@param     null
*@return    Return master volume value,value is a float type,the range of value is [0,1]
**/
float AML_HAL_Audio_Get_Volume ();

/**
*@brief     This API is used to device mute on/off
*@param     value is a bool type,TRUE means mute and FALSE means unmute
*@return    Return bool value,TRUE means setting is successful and FALSE means setting is failed.
**/
bool AML_HAL_Audio_Set_Mute(bool flag);


/**
*@brief     Get device mute state
*@param     null
*@return    Return bool type value,TRUE means mute and FALSE means unmute
**/
bool AML_HAL_Audio_Get_Mute();


/**
 * @brief   Set spdif mute/unmute
 * @param   flag is a bool type, TRUE means spdif mute and FALSE means unmute
 * @return  Return bool value, TRUE means setting is successful and FALSE means setting is failed.
 */
bool AML_HAL_Audio_Set_Spdif_Mute(bool flag);

/**
*@brief     Set audio output mode
*@param     Set the value of the output mode,value is a enum digital_format type
*@return    Return bool type value,TRUE is setting successful and FALSE is setting failed
**/
bool AML_HAL_Audio_Set_Output_Mode(enum digital_format mode);

/**
*@brief     Get device output model
*@param     null
*@return    Return output mode value,value is enum digital_format type
**/
enum digital_format AML_HAL_Audio_Get_Output_Mode();


/**
*@brief     Get device decode type according to the audio file format
*@param     Audio file format value,the value is enum AML_Src_Format type
*@return    Return decode type value,value is a enum AML_Decodetype type
**/
enum AML_DecodeType AML_HAL_Audio_Get_Decode_Type ( enum AML_Audio_Src_Format format);

/**
 * @brief   Get the HDMI output device support capability.
 * @param   null
 * @return  Return mask
**/
int AML_HAL_Audio_Capabilities_Get();

/**
*@brief     Set device track mode
*@param     Set the value of the track mode, value is a enum AML_Audio_TrackMode type
*@return    Return bool type value,TRUE is setting successful and FALSE is setting failed
**/
bool AML_HAL_Audio_Set_Track_Mode(enum AML_Audio_TrackMode mode);

/**
 * @brief   This APIis used to set AC4 dialog enhancer
 * @param   Set the value of dialog enhancer, range is 0 ~ 12
 * @return  Return bool type value, TRUE is setting successful and FALSE means setting is failed.
**/

/*the following are predefined ac4_de values*/
#define AC4_DIALOG_ENHANCER_OFF     0
#define AC4_DIALOG_ENHANCER_LOW     4
#define AC4_DIALOG_ENHANCER_MEDIUM  8
#define AC4_DIALOG_ENHANCER_HIGH    12

bool AML_HAL_Audio_Set_AC4_Dialog_Enhancer(int ac4_de);

#ifdef __cplusplus
}
#endif
#endif
