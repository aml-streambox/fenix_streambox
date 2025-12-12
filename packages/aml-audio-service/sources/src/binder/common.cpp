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

#include "common.h"

int posixOpenFile(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode) {
    int fd = shm_open(identifier, oflag, mode);
    if (fd == -1) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not get " + identifierLabel + " " + identifier + " data to file").c_str());
    }
    return fd;
}

int posixMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, void*& data, size_t length, int prot, int flags, int fd) {
    data = mmap(NULL, length, prot, flags, fd, 0);
    if (data == MAP_FAILED) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not map to " + identifierLabel + " " + identifier + " data").c_str());
        return -1;
    }
    return 0;
}

int posixOpenFileAndSetDataSize(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode, off_t length) {
    int fd = posixOpenFile(processNameLog, identifierLabel, identifier, oflag, mode);
    if (fd == -1) {
        return -1;
    }
    if (ftruncate(fd, length) == -1) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not configure " + identifierLabel + " " + identifier + " data size").c_str());
        return -1;
    }
    return fd;
}

int posixOpenFileSetDataSizeAndMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode, off_t length,
                                    void*& data, int prot, int flags) {
    int fd = posixOpenFile(processNameLog, identifierLabel, identifier, oflag, mode);
    if (fd == -1) {
        return -1;
    }
    if (ftruncate(fd, length) == -1) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not configure " + identifierLabel + " " + identifier + " data size").c_str());
        return -1;
    }
    if (posixMapData(processNameLog, identifierLabel, identifier, data, length, prot, flags, fd) == -1) {
        posixCloseFile(processNameLog, identifierLabel, identifier, fd);
        return -1;
    }
    return fd;
}

int posixOpenFileAndMapData(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int oflag, unsigned int mode,
                        void*& data, size_t length, int prot, int flags) {
    int fd = posixOpenFile(processNameLog, identifierLabel, identifier, oflag, mode);
    if (fd == -1) {
        return -1;
    }
    if (posixMapData(processNameLog, identifierLabel, identifier, data, length, prot, flags, fd) == -1) {
        posixCloseFile(processNameLog, identifierLabel, identifier, fd);
        return -1;
    }
    return fd;
}

int posixCloseFile(const std::string& processNameLog, const char* identifierLabel, const char* identifier, int fd) {
    if (close(fd) == -1) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not close file with " + identifierLabel + " " + identifier + " data").c_str());
        return -1;
    }
    return 0;
}

int posixUnmapDataCloseFileAndUnlinkName(const std::string& processNameLog, const char* identifierLabel, const char* identifier, void*& data, size_t length, int fd) {
    if (data == nullptr) {
        std::cout << processNameLog << " " << DEBUG_INFO << ", unmap completed or " << identifierLabel << " " << identifier << " data pointer set to null elsewhere." << std::endl;
    } else {
        if (munmap(data, length) == -1) {
            perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not unmap from " + identifierLabel + " " + identifier + " data").c_str());
            return -1;
        }
    }
    data = nullptr;
    if (posixCloseFile(processNameLog, identifierLabel, identifier, fd) == -1) {
        return -1;
    }
    if (shm_unlink(identifier) == -1) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not unlink name from " + identifierLabel + " " + identifier + " data").c_str());
        return -1;
    }
    return 0;
}

void SetAudioPermissions(const std::string& processNameLog, const char* file_path) {
    struct stat buf;
    if (stat(file_path, &buf) != 0) {
        perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not get information of " + file_path + " for set permission").c_str());
        return;
    }

    mode_t file_mode = buf.st_mode;
    if (S_ISDIR(file_mode)) {
        DIR* dir = opendir(file_path);
        if (dir == nullptr) {
            perror(std::string(processNameLog + " " + DEBUG_INFO + ", could not open directory " + file_path + " for set permission").c_str());
            return;
        }

        struct dirent* diread = readdir(dir);
        while (diread != nullptr) {
            const char* fname = diread->d_name;
            if (strncmp(fname, CURRENT_DIRECTORY, strlen(fname)) != 0 && strncmp(fname, PARENT_DIRECTORY, strlen(fname)) != 0) {
                char directory[PATH_MAX];

                strcpy(directory, file_path);
                strcat(directory, "/");
                strcat(directory, fname);

                SetAudioPermissions(processNameLog, directory);
            }
            diread = readdir(dir);
        }
        closedir(dir);
    } else {
        if ((file_mode & 07777) == (S_IRWXU | S_IRWXG | S_IRWXO)) return;

        std::cout << processNameLog << " Set audio permission for " << file_path << " to " << AUDIO_PERMISSION_STR << "." << std::endl;
        chmod(file_path, S_IRWXU | S_IRWXG | S_IRWXO);
    }
}