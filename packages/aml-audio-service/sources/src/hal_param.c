#include <stdio.h>
#include <stdlib.h>
#include <audio_if.h>

int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    int ret = audio_hw_load_interface(&device);

    if (argc < 3) {
        printf("Usage: hal_param <get/set> <param string (kvpair)>\n");
        return -1;
    }

    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return ret;
    }

    int inited = device->init_check(device);
    if (inited) {
        printf("device not inited, quit\n");
        audio_hw_unload_interface(device);
        return -1;
    }

    if (strcmp(argv[1], "get") == 0) {
        char *param = device->get_parameters(device, argv[2]);
        if (param) {
           printf("%s\n", param);
           free(param);
        }
    } else if (strcmp(argv[1], "set") == 0) {
        ret = device->set_parameters(device, argv[2]);
        if (!ret) {
            printf("Parameters sent to Audio HAL.\n");
        }
    } else {
        ret = device->set_parameters(device, argv[1]);
        if (!ret) {
            printf("Parameters sent to Audio HAL.\n");
        }
    }

    audio_hw_unload_interface(device);

    return ret;
}

