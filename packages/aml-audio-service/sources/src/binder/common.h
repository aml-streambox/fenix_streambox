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

#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <cstring>
#include <cstdlib>
#include <string.h>
#include <thread>
#include <chrono>
#include <mutex>
#include <condition_variable>
#include <unordered_set>
#include <unordered_map>

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>

#include <binder/Binder.h>

#include "audio_if.h"

#define NAME_OF_SERVICE "audio_service_binder"
#define MAX_NUM_TRIES_TO_GET_SERVICE 3
#define NUM_AUDIO_PORT_CONFIG_TYPES 3

struct {
    const int AUDIO_PORT_TYPE_DEVICE_COUNT_ID = 0,
            AUDIO_PORT_TYPE_MIX_COUNT_ID = 1,
            AUDIO_PORT_TYPE_SESSION_COUNT_ID = 2;
} audioPortTypeIds;

#define NUM_AUDIO_GAIN_VALUES 8

#define AUDIO_PORT_TYPE_DEVICE_ADDRESS "null"
// #define AUDIO_PORT_TYPE_DEVICE_ADDRESS_LENGTH std::min((int) strlen(AUDIO_PORT_TYPE_DEVICE_ADDRESS), AUDIO_DEVICE_MAX_ADDRESS_LEN - 1)

#define KSHAREDBUFFERSIZE 262144

#define INPUT_STREAM_LABEL "input stream pid-seq"
#define OUTPUT_STREAM_LABEL "output stream pid-seq"
#define DEBUG_INFO std::string(__func__) + " " + std::to_string(__LINE__)

#define BINDERFSPATH "/dev/binderfs"
#define POSIXSHMPATH "/dev/shm/uenvShm"
#define AUDIO_PERMISSION_STR "777"
#define STREAM_OBJECT_UMASK S_IWGRP // write access for other not removed
#define CURRENT_DIRECTORY "."
#define PARENT_DIRECTORY ".."

typedef enum {
    AUDIO_STREAM_OUT,
    AUDIO_STREAM_IN,
} audio_stream_direction;

struct {
    const std::string AUDIO_CLIENT_BINDER_TEST = "[AudioClientBinderTest]",
            AUDIO_CLIENT_BINDER = "[AudioClient]",
            AUDIO_SERVICE_BINDER = "[AudioServer]";
} processNameLogs;

#define BINDER_EXCEPTION -32
#define FIRST_CALL_TRANSACTION_VAL ::android::IBinder::FIRST_CALL_TRANSACTION

typedef enum {
    CMD_AS_GC = FIRST_CALL_TRANSACTION_VAL,
    CMD_AS_DCC = CMD_AS_GC + 1,
    CMD_AS_DIC = CMD_AS_DCC + 1,
    CMD_AS_DSVV = CMD_AS_DIC + 1,
    CMD_AS_DSMV = CMD_AS_DSVV + 1,
    CMD_AS_DGMV = CMD_AS_DSMV + 1,
    CMD_AS_DSM = CMD_AS_DGMV + 1,
    CMD_AS_DSMicM = CMD_AS_DSM + 1,
    CMD_AS_DGMicM = CMD_AS_DSMicM + 1,
    CMD_AS_DSP = CMD_AS_DGMicM + 1,
    CMD_AS_DGP = CMD_AS_DSP + 1,
    CMD_AS_DGIBS = CMD_AS_DGP + 1,
    CMD_AS_DOOS = CMD_AS_DGIBS + 1,
    CMD_AS_DCOS = CMD_AS_DOOS + 1,
    CMD_AS_DOIS = CMD_AS_DCOS + 1,
    CMD_AS_DCIS = CMD_AS_DOIS + 1,
    CMD_AS_DD = CMD_AS_DCIS + 1,
    CMD_AS_DSMasterM = CMD_AS_DD + 1,
    CMD_AS_DGMasterM = CMD_AS_DSMasterM + 1,
    CMD_AS_DCAP = CMD_AS_DGMasterM + 1,
    CMD_AS_DRAP = CMD_AS_DCAP + 1,
    CMD_AS_DSAPC = CMD_AS_DRAP + 1,
    CMD_AS_SGSR = CMD_AS_DSAPC + 1,
    CMD_AS_SGBS = CMD_AS_SGSR + 1,
    CMD_AS_SGC = CMD_AS_SGBS + 1,
    CMD_AS_SGF = CMD_AS_SGC + 1,
    CMD_AS_SS = CMD_AS_SGF + 1,
    CMD_AS_SGD = CMD_AS_SS + 1,
    CMD_AS_SSP = CMD_AS_SGD + 1,
    CMD_AS_SGP = CMD_AS_SSP + 1,
    CMD_AS_SO_GL = CMD_AS_SGP + 1,
    CMD_AS_SO_SV = CMD_AS_SO_GL + 1,
    CMD_AS_SO_W = CMD_AS_SO_SV + 1,
    CMD_AS_SO_GRP = CMD_AS_SO_W + 1,
    CMD_AS_SO_GNWT = CMD_AS_SO_GRP + 1,
    CMD_AS_SO_P = CMD_AS_SO_GNWT + 1,
    CMD_AS_SO_R = CMD_AS_SO_P + 1,
    CMD_AS_SO_F = CMD_AS_SO_R + 1,
    CMD_AS_SO_GPP = CMD_AS_SO_F + 1,
    CMD_AS_SI_SG = CMD_AS_SO_GPP + 1,
    CMD_AS_SI_R = CMD_AS_SI_SG + 1,
    CMD_AS_SI_GIFL = CMD_AS_SI_R + 1,
    CMD_AS_SI_GCP = CMD_AS_SI_GIFL + 1,
    CMD_AS_SP = CMD_AS_SI_GCP + 1,
    CMD_AS_ESP = CMD_AS_SP + 1,
    CMD_AS_EGP = CMD_AS_ESP + 1,
} transact_code;

// mode_t = unsigned int

extern int posixOpenFile(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode);

extern int posixMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, void*& data, size_t length, int prot, int flags, int fd);

extern int posixOpenFileAndSetDataSize(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode, off_t length);

extern int posixOpenFileSetDataSizeAndMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode, off_t length,
                                            void*& data, int prot, int flags);

extern int posixOpenFileAndMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode, void*& data, size_t length, int prot, int flags);

extern int posixCloseFile(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int fd);

extern int posixUnmapDataCloseFileAndUnlinkName(const std::string& processNameLog, const char* identifierLabel, const char* identifier, void*& data, size_t length, int fd);

extern void SetAudioPermissions(const std::string& processNameLog, const char* file_path);

#endif  // COMMON_H