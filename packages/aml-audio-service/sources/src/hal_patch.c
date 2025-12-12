#include <stdio.h>
#include <stdlib.h>
#include <audio_if.h>

int main(int argc, char **argv)
{
    audio_hw_device_t *device;
    struct audio_port_config source = {0};
    struct audio_port_config sink = {0};
    audio_patch_handle_t patch_handle;
    int ret, device_type;

    if (argc < 2) {
        fprintf(stderr, "Usage: hal_patch [source]\n");
        fprintf(stderr, "       0 -- CVBS\n");
        fprintf(stderr, "       1 -- HDMI\n");
        fprintf(stderr, "       2 -- SPDIF\n");
        return -1;
    }

    device_type = atoi(argv[1]);
    if (device_type == 0) {
        device_type = AUDIO_DEVICE_IN_LINE;
    } else if (device_type == 1) {
        device_type = AUDIO_DEVICE_IN_HDMI;
    } else if (device_type == 2) {
        device_type = AUDIO_DEVICE_IN_SPDIF;
    } else {
        fprintf(stderr, "Invalid input source.\n");
        return -1;
    }

    ret = audio_hw_load_interface(&device);
    if (ret) {
        fprintf(stderr, "audio_hw_load_interface failed: %d\n", ret);
        return -1;
    }

    source.id = 1;
    source.role = AUDIO_PORT_ROLE_SOURCE;                                 
    source.type = AUDIO_PORT_TYPE_DEVICE;                                 
    source.ext.device.type = device_type;                     
        
    memset(&sink, 0 , sizeof(struct audio_port_config));                  
    sink.id = 2;
    sink.role = AUDIO_PORT_ROLE_SINK;
    sink.type = AUDIO_PORT_TYPE_DEVICE;
    sink.ext.device.type = AUDIO_DEVICE_OUT_SPEAKER;                      
        
    ret = device->create_audio_patch(device, 1, &source, 1, &sink, &patch_handle);
    if (ret == 0) {
        printf("create device --> speaker patch %d.\n", patch_handle);
    }

    audio_hw_unload_interface(device);

    return 0;
}

