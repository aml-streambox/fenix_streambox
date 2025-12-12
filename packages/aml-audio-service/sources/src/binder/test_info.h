// Copyright 2023 Amlogic, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef TEST_INFO_H
#define TEST_INFO_H

struct {
        const int SIZE_OF_TOKEN = 100;
        const int TEST_HEADER_LENGTH = 80;
        const std::string PREREQ_TEST_NAME = "GET BINDER CLIENT AND BINDER SERVICE",
                DCC_TEST_NAME = "DEVICE COMMON CLOSE",
                DIC_TEST_NAME = "DEVICE_INIT_CHECK",
                DSVV_TEST_NAME = "DEVICE_SET_VOICE_VOLUME",
                DSMV_TEST_NAME = "DEVICE_SET_MASTER_VOLUME",
                DGMV_TEST_NAME = "DEVICE_GET_MASTER_VOLUME",
                DSM_TEST_NAME = "DEVICE_SET_MODE",
                DCAP_TEST_NAME = "DEVICE_CREATE_AUDIO_PATCH",
                DSMicM_TEST_NAME = "DEVICE_SET_MIC_MUTE",
                DGMicM_TEST_NAME = "DEVICE_GET_MIC_MUTE",
                DSP_TEST_NAME = "DEVICE_SET_PARAMETERS",
                DGP_TEST_NAME = "DEVICE_GET_PARAMETERS",
                DOOS_TEST_NAME = "DEVICE_OPEN_OUTPUT_STREAM",
                DD_TEST_NAME = "DEVICE_DUMP",
                DGMasterM_TEST_NAME = "DEVICE_GET_MASTER_MUTE",
                SP_TEST_NAME = "SERVICE_PING";

        const char* DIGITAL_MODE_KEY = "hdmi_format";
        // const char* TRACK_MODE_KEY = "sound_track";

} testInfo;

#endif  // TEST_INFO_H