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


#ifndef __AML_AUDIO_SETTING_H__
#define __AML_AUDIO_SETTING_H__

#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

enum AudioPort_t {
  AUDIO_PORT_MIN   = -1,
  AUDIO_PORT_HDMI   = 0,
  AUDIO_PORT_HEADPHONE = 1,
  AUDIO_PORT_MAX    = 2,
};

enum audio_digital_mode {
  AML_HAL_PCM = 0,
  AML_HAL_DD = 1,
  AML_HAL_AUTO = 2,
  AML_HAL_BYPASS = 3,
  AML_HAL_DDP = 4,
};

enum audio_drc_mode {
  DRC_RF = 0,
  DRC_LINE = 1,
  DRC_OFF = 2,
};

enum aud_codec_types {
  AUD_CODEC_TYPE_STEREO_PCM     = 0x0,
  AUD_CODEC_TYPE_DTS_RAW_MODE   = 0x1,
  AUD_CODEC_TYPE_AC3            = 0x2,
  AUD_CODEC_TYPE_DTS            = 0x3,
  AUD_CODEC_TYPE_EAC3           = 0x4,
  AUD_CODEC_TYPE_DTS_HD         = 0x5,
  AUD_CODEC_TYPE_MULTI_LPCM     = 0x6,
  AUD_CODEC_TYPE_TRUEHD         = 0x7,
  AUD_CODEC_TYPE_DTS_HD_MA      = 0x8,
  AUD_CODEC_TYPE_HSR_STEREO_PCM = 0x9,
  AUD_CODEC_TYPE_AC3_LAYOUT_B   = 0xa,
  AUD_CODEC_TYPE_OBA            = 0xb,
};

/*
*@brief     set hdmi connect status via kcontrol
*@param     isconnect: connect(true) or unconnect(false)
*@return    Return int type value,0 is setting successful and <0 is setting failed
*/
int aml_audio_set_hdmi_param(bool isconnect);

/*
*@brief     set volume via kcontrol
*@param     Set volume value,The range of the value is [0,100],value is a int type
*@return    Return int type value,0 is setting successful and <0 is setting failed
*/
int aml_audio_set_volume(int value);

/*
*@brief     get volume via kcontrol
*@return    Return volume value (int type)
*/
int aml_audio_get_volume();

/*
*@brief     set mute via kcontrol
*@param     port: which port wanted to be controlled, refer to AudioPort_t; mute: mute(ture) or unmute(false)
*@return    Return int type value,0 is setting successful and <0 is setting failed
*/
int aml_audio_set_mute(int port, bool mute);

/*
*@brief     get mute via kcontrol
*@param     port: which port wanted to be controlled, refer to AudioPort_t
*@return    Return mute value (bool type), ture is mute and false is unmute
*/
bool aml_audio_get_mute(int port);

/*
*@brief     set digital mode via kcontrol
*@param     mode: audio digital enumeration type
*@return    Return int type value,0 is setting successful, and <0 is setting failed
*/
int aml_audio_set_digital_mode(enum audio_digital_mode mode);

/*
*@brief     get digital mode via kcontrol
*@return    Return audio digital mode
*/
int aml_audio_get_digital_mode();

/*
*@brief     set drc mode via kcontrol
*@param     mode: audio drc enumeration type
*@return    Return int type value,0 is setting successful, and <0 is setting failed
*/
int aml_audio_set_drc_mode(enum audio_drc_mode mode);

/*
*@brief     get drc mode via kcontrol
*@return    Return audio drc mode
*/
int aml_audio_get_drc_mode();

/*
*@brief     get spdif format via kcontrol
*@return    Return audio spdif format
*/
int aml_audio_get_spdif_format();

#ifdef __cplusplus
}
#endif
#endif
