#ifndef IpcBuffer_c_
#define IpcBuffer_c_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

extern void *IpcBuffer_create(const char *name, size_t size);

extern void IpcBuffer_destroy(void *cb);

extern void IpcBuffer_write(void *cb, const unsigned char *buf, int size);

extern uint8_t *IpcBuffer_get_ptr(const char *name);

extern uint64_t IpcBuffer_get_wr_pos(const char *name);

extern size_t IpcBuffer_get_capacity(const char *name);

extern void *IpcBuffer_get_by_name(const char *name);

extern void IpcBuffer_set_water_level_byname(const char *name, size_t level);

extern void IpcBuffer_inc_underrun_byname(const char *name);

extern void IpcBuffer_add_silence_byname(const char *name, size_t size);

extern void IpcBuffer_set_water_level(void *instance, size_t level);

extern void IpcBuffer_inc_underrun(void *instance);

extern void IpcBuffer_setMeta(void *instance, uint64_t meta_64, uint32_t meta_32);

extern void IpcBuffer_add_silence(void *instance, size_t size);

#ifdef __cplusplus
}
#endif

#endif /* IpcBuffer_c_ */

