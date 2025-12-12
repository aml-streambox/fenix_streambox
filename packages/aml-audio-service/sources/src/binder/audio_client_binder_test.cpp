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

#include <cstdio>
#include <binder/IPCThreadState.h>
#include <binder/ProcessState.h>

#include "AML_HAL_Audio.h"
#include "audio_client_binder.h"
#include "test_info.h"

#define CHK_CLIENT(m, n) \
    do { \
        if (mAudioClientBinder == nullptr) { \
            std::cout << PROCESS_NAME_INFO << " " << (m) << std::endl; \
            printTestFail(PROCESS_NAME_INFO, (n)); std::cout << std::endl; return false; \
        } \
    } while (0)

void printTestSuccess(const std::string& PROCESS_NAME_INFO, const std::string& TEST_NAME) {
    std::cout << PROCESS_NAME_INFO << " " << TEST_NAME;
    if (TEST_NAME != testInfo.PREREQ_TEST_NAME) {
        std::cout << " test";
    }
    std::cout << " successful." << std::endl;
}

void printTestFail(const std::string& PROCESS_NAME_INFO, const std::string& TEST_NAME) {
    std::cout << PROCESS_NAME_INFO << " " << TEST_NAME;
    if (TEST_NAME != testInfo.PREREQ_TEST_NAME) { std::cout << " test"; }
    std::cout << " fail." << std::endl;
}

void printSuccess() {
    std::cout << "Audio client binder test successful." << std::endl;
}

void printFail() {
    std::cout << "Audio client binder test fail." << std::endl;
}

void printTestHeader(const std::string& PROCESS_NAME_INFO, const std::string& TEST_NAME) {
    for (int i = 0; i < testInfo.TEST_HEADER_LENGTH; i++) { std::cout << "#"; }
    std::cout << std::endl;

    std::cout << PROCESS_NAME_INFO << " " << TEST_NAME;
    if (TEST_NAME != testInfo.PREREQ_TEST_NAME) { std::cout << " test"; }
    std::cout << std::endl;

    for (int i = 0; i < testInfo.TEST_HEADER_LENGTH; i++) { std::cout << "#"; }
    std::cout << std::endl;
}

// int setParameter(::android::sp<AudioClientBinder> mAudioClientBinder, const char* key, int mode) {
//     const int CMD_LENGTH = 256; char cmd[CMD_LENGTH] = {0};
//     snprintf(cmd, sizeof(cmd), "%s=%d", key, mode);
//     return mAudioClientBinder->Device_set_parameters(cmd);
// }

int setParameter(::android::sp<AudioClientBinder> mAudioClientBinder, const char* key, digital_format mode) {
    const int CMD_LENGTH = 256; char cmd[CMD_LENGTH] = {0};
    snprintf(cmd, sizeof(cmd), "%s=%d", key, mode);
    return mAudioClientBinder->Device_set_parameters(cmd);
}

// int setParameter(::android::sp<AudioClientBinder> mAudioClientBinder, const char* key, AML_Audio_TrackMode mode) {
//     const int CMD_LENGTH = 256; char cmd[CMD_LENGTH] = {0};
//     snprintf(cmd, sizeof(cmd), "%s=%d", key, mode);
//     return mAudioClientBinder->Device_set_parameters(cmd);
// }

bool prerequisite(::android::sp<AudioClientBinder>& mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string prereqTestName = testInfo.PREREQ_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, prereqTestName);

    mAudioClientBinder = new AudioClientBinder();

    CHK_CLIENT("Could not get instance of client.", prereqTestName);
    if (!mAudioClientBinder->gotService()) {
        std::cout << "\n" << PROCESS_NAME_INFO << " Could not get instance of service." << std::endl;
        printTestFail(PROCESS_NAME_INFO, prereqTestName); std::cout << std::endl; return false;
    }

    printTestSuccess(PROCESS_NAME_INFO, prereqTestName); std::cout << std::endl; return true;
}

// bool deviceCommonCloseTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
//     const std::string dccTestName = testInfo.DCC_TEST_NAME;
//     printTestHeader(PROCESS_NAME_INFO, dccTestName);

//     int ret = mAudioClientBinder->Device_common_close();
//     if (ret) { printTestFail(PROCESS_NAME_INFO, dccTestName); std::cout << std::endl; return false; }

//     printTestSuccess(PROCESS_NAME_INFO, dccTestName); std::cout << std::endl; return true;
// }

bool deviceInitCheckTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dicTestName = testInfo.DIC_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dicTestName);

    CHK_CLIENT("Instance of client is null.", dicTestName);
    int ret = mAudioClientBinder->Device_init_check();
    if (ret) { printTestFail(PROCESS_NAME_INFO, dicTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dicTestName); std::cout << std::endl; return true;
}

bool deviceSetVoiceVolumeTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dsvvTestName = testInfo.DSVV_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dsvvTestName);

    float volume;
    std::cout << PROCESS_NAME_INFO << " Enter a voice volume (0.0 - 1.0): ";
    std::cin >> volume;

    CHK_CLIENT("Instance of client is null.", dsvvTestName);
    int ret = mAudioClientBinder->Device_set_voice_volume(volume);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsvvTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dsvvTestName); std::cout << std::endl; return true;
}

bool deviceSetMasterVolumeTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dsmvTestName = testInfo.DSMV_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dsmvTestName);

    float volume;
    std::cout << PROCESS_NAME_INFO << " Enter a master volume (0.0 - 1.0): ";
    std::cin >> volume;

    CHK_CLIENT("Instance of client is null.", dsmvTestName);
    int ret = mAudioClientBinder->Device_set_master_volume(volume);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmvTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dsmvTestName); std::cout << std::endl; return true;
}

bool deviceGetMasterVolumeTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dgmvTestName = testInfo.DGMV_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dgmvTestName);

    CHK_CLIENT("Instance of client is null.", dgmvTestName);

    float masterVolume;
    int ret = mAudioClientBinder->Device_get_master_volume(masterVolume);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dgmvTestName); std::cout << std::endl; return false; }

    std::cout << PROCESS_NAME_INFO << " master volume: " << masterVolume << "." << std::endl;

    printTestSuccess(PROCESS_NAME_INFO, dgmvTestName); std::cout << std::endl; return true;
}

bool deviceSetModeTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dsmTestName = testInfo.DSM_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dsmTestName);

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_INVALID << "." << std::endl;
    int ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_INVALID);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_CURRENT << "." << std::endl;
    ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_CURRENT);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_RINGTONE << "." << std::endl;
    ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_RINGTONE);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_IN_CALL << "." << std::endl;
    ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_IN_CALL);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_IN_COMMUNICATION << "." << std::endl;
    ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_IN_COMMUNICATION);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mode to " << AUDIO_MODE_NORMAL << "." << std::endl;
    ret = mAudioClientBinder->Device_set_mode(AUDIO_MODE_NORMAL);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dsmTestName); std::cout << std::endl; return true;
}

bool deviceSetMicMuteTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dsmicmTestName = testInfo.DSMicM_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dsmicmTestName);

    int ret;

    CHK_CLIENT("Instance of client is null.", dsmicmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mic mute to false." << std::endl;
    ret = mAudioClientBinder->Device_set_mic_mute(false);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmicmTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dsmicmTestName);
    std::cout << PROCESS_NAME_INFO << " Set mic mute to true." << std::endl;
    ret = mAudioClientBinder->Device_set_mic_mute(true);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dsmicmTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dsmicmTestName); std::cout << std::endl; return true;
}

bool deviceGetMicMuteTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dgmicmTestName = testInfo.DGMicM_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dgmicmTestName);

    CHK_CLIENT("Instance of client is null.", dgmicmTestName);

    bool mute;
    int ret = mAudioClientBinder->Device_get_mic_mute(mute);

    if (ret) { printTestFail(PROCESS_NAME_INFO, dgmicmTestName); std::cout << std::endl; return false; }

    std::cout << PROCESS_NAME_INFO << " mic mute: " << (mute ? "true" : "false") << "." << std::endl;

    printTestSuccess(PROCESS_NAME_INFO, dgmicmTestName); std::cout << std::endl; return true;
}

bool deviceSetParametersTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dspTestName = testInfo.DSP_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dspTestName);

    int ret;
    const char* digitalModeKey = testInfo.DIGITAL_MODE_KEY;
    // const char* trackModeKey = testInfo.TRACK_MODE_KEY;

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_ERROR." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_ERROR);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_PCM." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_PCM);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_DD." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_DD);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_Bypass." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_Bypass);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_DDP." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_DDP);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to 0." << std::endl;
    // ret = setParameter(mAudioClientBinder, digitalModeKey, 0);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    CHK_CLIENT("Instance of client is null.", dspTestName);
    std::cout << PROCESS_NAME_INFO << " Setting " << digitalModeKey << " to AML_HAL_Auto." << std::endl;
    ret = setParameter(mAudioClientBinder, digitalModeKey, digital_format::AML_HAL_Auto);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << trackModeKey << " to AML_AUDIO_TRACKMODE_STEREO." << std::endl;
    // ret = setParameter(mAudioClientBinder, trackModeKey, AML_Audio_TrackMode::AML_AUDIO_TRACKMODE_STEREO);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << trackModeKey << " to AML_AUDIO_TRACKMODE_DUAL_LEFT." << std::endl;
    // ret = setParameter(mAudioClientBinder, trackModeKey, AML_Audio_TrackMode::AML_AUDIO_TRACKMODE_DUAL_LEFT);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << trackModeKey << " to AML_AUDIO_TRACKMODE_DUAL_RIGHT." << std::endl;
    // ret = setParameter(mAudioClientBinder, trackModeKey, AML_Audio_TrackMode::AML_AUDIO_TRACKMODE_DUAL_RIGHT);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << trackModeKey << " to AML_AUDIO_TRACKMODE_SWAP." << std::endl;
    // ret = setParameter(mAudioClientBinder, trackModeKey, AML_Audio_TrackMode::AML_AUDIO_TRACKMODE_SWAP);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    // CHK_CLIENT("Instance of client is null.", dspTestName);
    // std::cout << PROCESS_NAME_INFO << " Setting " << trackModeKey << " to AML_AUDIO_TRACKMODE_MIX." << std::endl;
    // ret = setParameter(mAudioClientBinder, trackModeKey, AML_Audio_TrackMode::AML_AUDIO_TRACKMODE_MIX);
    // if (ret) { printTestFail(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return false; }

    printTestSuccess(PROCESS_NAME_INFO, dspTestName); std::cout << std::endl; return true;
}

bool deviceGetParametersTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dgpTestName = testInfo.DGP_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dgpTestName);

    CHK_CLIENT("Instance of client is null.", dgpTestName);

    char* params = nullptr;
    const char* digitalModeKey = testInfo.DIGITAL_MODE_KEY;
    // const char* trackModeKey = testInfo.TRACK_MODE_KEY;

    params = mAudioClientBinder->Device_get_parameters(digitalModeKey);
    if (!params) { printTestFail(PROCESS_NAME_INFO, dgpTestName); std::cout << std::endl; return false; }

    std::cout << PROCESS_NAME_INFO << " " << params << "." << std::endl;

    free(params);

    // CHK_CLIENT("Instance of client is null.", dgpTestName);

    // params = mAudioClientBinder->Device_get_parameters(trackModeKey);
    // if (!params) { printTestFail(PROCESS_NAME_INFO, dgpTestName); std::cout << std::endl; return false; }

    // std::cout << PROCESS_NAME_INFO << " " << params << "." << std::endl;

    // free(params);

    printTestSuccess(PROCESS_NAME_INFO, dgpTestName); std::cout << std::endl; return true;
}

bool deviceDumpTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string ddTestName = testInfo.DD_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, ddTestName);

    CHK_CLIENT("Instance of client is null.", ddTestName);

    std::string deviceDump;
    int ret = mAudioClientBinder->Device_dump(deviceDump);
    if (ret) { printTestFail(PROCESS_NAME_INFO, ddTestName); std::cout << std::endl; return false; }

    std::cout << PROCESS_NAME_INFO << " Device dump:\n" << deviceDump << "." << std::endl;

    printTestSuccess(PROCESS_NAME_INFO, ddTestName); std::cout << std::endl; return true;
}

bool deviceGetMasterMuteTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string dgmastermTestName = testInfo.DGMasterM_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, dgmastermTestName);

    CHK_CLIENT("Instance of client is null.", dgmastermTestName);

    bool mute;
    int ret = mAudioClientBinder->Device_get_master_mute(mute);
    if (ret) { printTestFail(PROCESS_NAME_INFO, dgmastermTestName); std::cout << std::endl; return false; }

    std::cout << PROCESS_NAME_INFO << " master mute: " << (mute ? "true" : "false") << "." << std::endl;

    printTestSuccess(PROCESS_NAME_INFO, dgmastermTestName); std::cout << std::endl; return true;
}

bool servicePingTest(::android::sp<AudioClientBinder> mAudioClientBinder, const std::string& PROCESS_NAME_INFO) {
    const std::string servicePingTestName = testInfo.SP_TEST_NAME;
    printTestHeader(PROCESS_NAME_INFO, servicePingTestName);

    std::cout << "Attempt service ping." << std::endl;

    CHK_CLIENT("Instance of client is null.", servicePingTestName);

    int status_32;
    int ret = mAudioClientBinder->Service_ping(status_32);

    if (ret || status_32 != 0) {
        std::cout << PROCESS_NAME_INFO << " Service ping unsuccessful. status_32: " << status_32 << "." << std::endl;
        printTestFail(PROCESS_NAME_INFO, servicePingTestName); std::cout << std::endl; return false;
    }

    std::cout << PROCESS_NAME_INFO << " Service ping successful. status_32: " << status_32 << "." << std::endl;
    printTestSuccess(PROCESS_NAME_INFO, servicePingTestName); std::cout << std::endl; return true;
}

int main(int argc, char** argv) {
    ::android::sp<::android::ProcessState> proc(::android::ProcessState::self());
    proc->startThreadPool();

    ::android::sp<AudioClientBinder> mAudioClientBinder;
    const std::string PROCESS_NAME_INFO = processNameLogs.AUDIO_CLIENT_BINDER_TEST;

    std::cout << PROCESS_NAME_INFO << " Begin audio client binder test.\n" << std::endl;

    bool prerequisiteStatus = prerequisite(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!prerequisiteStatus) { printFail(); return 0; }

    // bool deviceCommonCloseTestStatus = deviceCommonCloseTest(mAudioClientBinder, PROCESS_NAME_INFO);
    // if (!deviceCommonCloseTestStatus) { printFail(); return 0; }

    bool deviceInitCheckTestStatus = deviceInitCheckTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceInitCheckTestStatus) { printFail(); return 0; }

    bool deviceSetVoiceVolumeTestStatus = deviceSetVoiceVolumeTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceSetVoiceVolumeTestStatus) { printFail(); return 0; }

    bool deviceSetMasterVolumeTestStatus = deviceSetMasterVolumeTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceSetMasterVolumeTestStatus) { printFail(); return 0; }

    bool deviceGetMasterVolumeTestStatus = deviceGetMasterVolumeTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceGetMasterVolumeTestStatus) { printFail(); return 0; }

    bool deviceSetModeTestStatus = deviceSetModeTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceSetModeTestStatus) { printFail(); return 0; }

    bool deviceSetMicMuteTestStatus = deviceSetMicMuteTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceSetMicMuteTestStatus) { printFail(); return 0; }

    bool deviceGetMicMuteTestStatus = deviceGetMicMuteTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceGetMicMuteTestStatus) { printFail(); return 0; }

    std::cout << PROCESS_NAME_INFO << " Set mic mute to false." << std::endl;
    int ret = mAudioClientBinder->Device_set_mic_mute(false);
    if (ret) { printFail(); return 0; }

    std::cout << std::endl;

    bool deviceSetParametersStatus = deviceSetParametersTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceSetParametersStatus) { printFail(); return 0; }

    bool deviceGetParametersStatus = deviceGetParametersTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceGetParametersStatus) { printFail(); return 0; }

    bool deviceDumpTestStatus = deviceDumpTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceDumpTestStatus) { printFail(); return 0; }

    bool deviceGetMasterMuteTestStatus = deviceGetMasterMuteTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!deviceGetMasterMuteTestStatus) { printFail(); return 0; }

    bool servicePingTestStatus = servicePingTest(mAudioClientBinder, PROCESS_NAME_INFO);
    if (!servicePingTestStatus) { printFail(); return 0; }

    printSuccess();

    if (mAudioClientBinder != nullptr) {
        mAudioClientBinder.clear();
    }

    return 0;
}