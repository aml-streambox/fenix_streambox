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

#include <binder/ProcessState.h>
#include <binder/IServiceManager.h>

#include <execinfo.h>
#include <signal.h>

#include "audio_service_binder.h"

void handler(int sig)
{
    void *array[100];
    size_t size, i = 0;
    char ** trace;

    // get void*'s for all entries on the stack
    size = backtrace(array, 100);

    // print out all the frames to stderr
    fprintf(stderr, "Error: signal %d, size %d\n", sig, size);
    ALOGE("Error: signal %d, size %d", sig, size);
    trace = backtrace_symbols(array, size);

    if (trace) {
        for (i = 0; i < size; i++) {
            ALOGE("%s", trace[i]);
            fprintf(stderr, "%s\n", trace[i]);
        }
    } else {
        fprintf(stderr, "backtrace symbols error!!!\n");
        ALOGE("backtrace symbols error!!!");
    }

    exit(1);
}

int main(int argc, char** argv) {
    signal(SIGSEGV, handler);
    signal(SIGABRT, handler);
    signal(SIGFPE, handler);

    AudioServiceBinder* mAudioService = AudioServiceBinder::GetInstance();
    ::android::sp<::android::ProcessState> proc(::android::ProcessState::self());
    ::android::sp<::android::IServiceManager> serviceManager = ::android::defaultServiceManager();

    const char* nameOfService = NAME_OF_SERVICE;
    serviceManager->addService(::android::String16(nameOfService), mAudioService);

    proc->startThreadPool();

    std::cout << processNameLogs.AUDIO_SERVICE_BINDER << " Start audio server." << std::endl;

    while (true) {
        std::this_thread::sleep_for(std::chrono::microseconds(500*1000));
    }

    return 0;
}