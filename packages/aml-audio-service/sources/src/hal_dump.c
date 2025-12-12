#include <stdio.h>
#include <stdlib.h>
#include <audio_if.h>

int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    char *dump;
    int ret = audio_hw_load_interface(&device);

    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return -1;
    }

    dump = device->dump(device, 0);
    if (dump) {
        printf("%s", dump);
        free(dump);
    }

    audio_hw_unload_interface(device);

    return 0;
}

