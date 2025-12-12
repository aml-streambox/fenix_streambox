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
#define LOG_TAG "AML_Audio_Setting"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <ctype.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <pthread.h>
#include <linux/ioctl.h>
#define __force
#define __bitwise
#define __user
#include <sound/asound.h>
#include "AML_Audio_Setting.h"
#include <cutils/log.h>

#ifndef SNDRV_CTL_ELEM_ID_NAME_MAXLEN
#define SNDRV_CTL_ELEM_ID_NAME_MAXLEN 44
#endif
#define DEFAULT_AML_SOUND_CARD 0
/* TLV header size*/
#define TLV_HEADER_SIZE (2 * sizeof(unsigned int))

#define TDMB_GAIN "TDMOUT_B Software Gain"
#define TDMA_GAIN "TDMOUT_A Software Gain"
#define AML_CHIP_ID "AML chip id"
#define AML_CHIP_ID_S1A 69
#define HDMI_OUT_MUTE "Audio hdmi-out mute"
#define DAC_DIGITAL_VOLUME "DAC Digital Playback Volume"
#define DIGITAL_MODE "Audio Digital Mode"
#define DRC_CONTROL "Audio DRC Control"
#define HDMI_CON "Audio Output Select"
#define SPDIF_FORMAT "Audio spdif format"
#define DAC_DIGITAl_DEFAULT_VOLUME          (251)
#define HEADPHONE_DAC_CHANNEL_NUM    (2)

#define DRC_MODE_LINE 2
#define DRC_MODE_RF 3
#define DRC_MODE_BIT  0
#define DRC_HIGH_CUT_BIT 3
#define DRC_LOW_BST_BIT 16

extern "C" {

struct mixer_ctl {
    struct mixer *mixer;
    struct snd_ctl_elem_info *info;
    char **ename;
    bool info_retrieved;
};

struct mixer {
    int fd;
    struct snd_ctl_card_info card_info;
    struct snd_ctl_elem_info *elem_info;
    struct mixer_ctl *ctl;
    unsigned int count;
};

/* Mixer control types */
enum mixer_ctl_type {
    MIXER_CTL_TYPE_BOOL,
    MIXER_CTL_TYPE_INT,
    MIXER_CTL_TYPE_ENUM,
    MIXER_CTL_TYPE_BYTE,
    MIXER_CTL_TYPE_IEC958,
    MIXER_CTL_TYPE_INT64,
    MIXER_CTL_TYPE_UNKNOWN,

    MIXER_CTL_TYPE_MAX,
};

static pthread_mutex_t g_volume_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t g_mute_lock = PTHREAD_MUTEX_INITIALIZER;
static int reserved_volume = 30;
static int chip_id = 0;

static void _mixer_close(struct mixer *mixer)
{
    unsigned int n,m;

    if (!mixer)
        return;

    if (mixer->fd >= 0)
        close(mixer->fd);

    if (mixer->ctl) {
        for (n = 0; n < mixer->count; n++) {
            if (mixer->ctl[n].ename) {
                unsigned int max = mixer->ctl[n].info->value.enumerated.items;
                for (m = 0; m < max; m++)
                    free(mixer->ctl[n].ename[m]);
                free(mixer->ctl[n].ename);
            }
        }
        free(mixer->ctl);
    }

    if (mixer->elem_info)
        free(mixer->elem_info);

    free(mixer);

    /* TODO: verify frees */
}

static struct mixer *_mixer_open(unsigned int card)
{
    struct snd_ctl_elem_list elist;
    struct snd_ctl_elem_id *eid = NULL;
    struct mixer *mixer = NULL;
    unsigned int n;
    int fd;
    char fn[256];

    snprintf(fn, sizeof(fn), "/dev/snd/controlC%u", card);
    fd = open(fn, O_RDWR);
    if (fd < 0)
        return 0;

    memset(&elist, 0, sizeof(elist));
    if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &elist) < 0)
        goto fail;

    mixer = (struct mixer *)calloc(1, sizeof(*mixer));
    if (!mixer)
        goto fail;

    mixer->ctl = (struct mixer_ctl *)calloc(elist.count, sizeof(struct mixer_ctl));
    mixer->elem_info = (struct snd_ctl_elem_info *)calloc(elist.count, sizeof(struct snd_ctl_elem_info));
    if (!mixer->ctl || !mixer->elem_info)
        goto fail;

    if (ioctl(fd, SNDRV_CTL_IOCTL_CARD_INFO, &mixer->card_info) < 0)
        goto fail;

    eid = (struct snd_ctl_elem_id *)calloc(elist.count, sizeof(struct snd_ctl_elem_id));
    if (!eid)
        goto fail;

    mixer->count = elist.count;
    mixer->fd = fd;
    elist.space = mixer->count;
    elist.pids = eid;
    if (ioctl(fd, SNDRV_CTL_IOCTL_ELEM_LIST, &elist) < 0)
        goto fail;

    for (n = 0; n < mixer->count; n++) {
        struct mixer_ctl *ctl = mixer->ctl + n;

        ctl->mixer = mixer;
        ctl->info = mixer->elem_info + n;
        ctl->info->id.numid = eid[n].numid;
        strncpy((char *)ctl->info->id.name, (char *)eid[n].name,
                SNDRV_CTL_ELEM_ID_NAME_MAXLEN);
        ctl->info->id.name[SNDRV_CTL_ELEM_ID_NAME_MAXLEN - 1] = 0;
    }

    free(eid);
    return mixer;

fail:
    /* TODO: verify frees in failure case */
    if (eid)
        free(eid);
    if (mixer)
        _mixer_close(mixer);
    else if (fd >= 0)
        close(fd);
    return 0;
}

static bool _mixer_ctl_get_elem_info(struct mixer_ctl* ctl)
{
    if (!ctl->info_retrieved) {
        if (ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_INFO, ctl->info) < 0)
            return false;
        ctl->info_retrieved = true;
    }

    if (ctl->info->type != SNDRV_CTL_ELEM_TYPE_ENUMERATED || ctl->ename)
        return true;

    struct snd_ctl_elem_info tmp;
    char** enames = (char**)calloc(ctl->info->value.enumerated.items, sizeof(char*));
    if (!enames)
        return false;

    for (unsigned int i = 0; i < ctl->info->value.enumerated.items; i++) {
        memset(&tmp, 0, sizeof(tmp));
        tmp.id.numid = ctl->info->id.numid;
        tmp.value.enumerated.item = i;
        if (ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_INFO, &tmp) < 0)
            goto fail;
        enames[i] = strdup(tmp.value.enumerated.name);
        if (!enames[i])
            goto fail;
    }
    ctl->ename = enames;
    return true;

fail:
    free(enames);
    return false;
}

static const char *_mixer_get_name(struct mixer *mixer)
{
    return (const char *)mixer->card_info.name;
}

static unsigned int _mixer_get_num_ctls(struct mixer *mixer)
{
    if (!mixer)
        return 0;

    return mixer->count;
}

static struct mixer_ctl *_mixer_get_ctl(struct mixer *mixer, unsigned int id)
{
    struct mixer_ctl *ctl;

    if (!mixer || (id >= mixer->count))
        return NULL;

    ctl = mixer->ctl + id;
    if (!_mixer_ctl_get_elem_info(ctl))
        return NULL;

    return ctl;
}

static struct mixer_ctl *_mixer_get_ctl_by_name(struct mixer *mixer, const char *name)
{
    unsigned int n;

    if (!mixer)
        return NULL;

    for (n = 0; n < mixer->count; n++)
        if (!strcmp(name, (char*) mixer->elem_info[n].id.name))
            return _mixer_get_ctl(mixer, n);

    return NULL;
}

static void _mixer_ctl_update(struct mixer_ctl *ctl)
{
    ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_INFO, ctl->info);
}

static const char *_mixer_ctl_get_name(struct mixer_ctl *ctl)
{
    if (!ctl)
        return NULL;

    return (const char *)ctl->info->id.name;
}

static enum mixer_ctl_type _mixer_ctl_get_type(struct mixer_ctl *ctl)
{
    if (!ctl)
        return MIXER_CTL_TYPE_UNKNOWN;

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:    return MIXER_CTL_TYPE_BOOL;
    case SNDRV_CTL_ELEM_TYPE_INTEGER:    return MIXER_CTL_TYPE_INT;
    case SNDRV_CTL_ELEM_TYPE_ENUMERATED: return MIXER_CTL_TYPE_ENUM;
    case SNDRV_CTL_ELEM_TYPE_BYTES:      return MIXER_CTL_TYPE_BYTE;
    case SNDRV_CTL_ELEM_TYPE_IEC958:     return MIXER_CTL_TYPE_IEC958;
    case SNDRV_CTL_ELEM_TYPE_INTEGER64:  return MIXER_CTL_TYPE_INT64;
    default:                             return MIXER_CTL_TYPE_UNKNOWN;
    };
}

static const char *_mixer_ctl_get_type_string(struct mixer_ctl *ctl)
{
    if (!ctl)
        return "";

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:    return "BOOL";
    case SNDRV_CTL_ELEM_TYPE_INTEGER:    return "INT";
    case SNDRV_CTL_ELEM_TYPE_ENUMERATED: return "ENUM";
    case SNDRV_CTL_ELEM_TYPE_BYTES:      return "BYTE";
    case SNDRV_CTL_ELEM_TYPE_IEC958:     return "IEC958";
    case SNDRV_CTL_ELEM_TYPE_INTEGER64:  return "INT64";
    default:                             return "Unknown";
    };
}

static unsigned int _mixer_ctl_get_num_values(struct mixer_ctl *ctl)
{
    if (!ctl)
        return 0;

    return ctl->info->count;
}

static int percent_to_int(struct snd_ctl_elem_info *ei, int percent)
{
    int range;

    if (percent > 100)
        percent = 100;
    else if (percent < 0)
        percent = 0;

    range = (ei->value.integer.max - ei->value.integer.min);

    return ei->value.integer.min + (range * percent) / 100;
}

static int int_to_percent(struct snd_ctl_elem_info *ei, int value)
{
    int range = (ei->value.integer.max - ei->value.integer.min);

    if (range == 0)
        return 0;

    return ((value - ei->value.integer.min) / range) * 100;
}

static int _mixer_ctl_set_value(struct mixer_ctl *ctl, unsigned int id, int value)
{
    struct snd_ctl_elem_value ev;
    int ret;

    if (!ctl || (id >= ctl->info->count))
        return -EINVAL;

    memset(&ev, 0, sizeof(ev));
    ev.id.numid = ctl->info->id.numid;
    ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_READ, &ev);
    if (ret < 0)
        return ret;

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:
        ev.value.integer.value[id] = !!value;
        break;

    case SNDRV_CTL_ELEM_TYPE_INTEGER:
        ev.value.integer.value[id] = value;
        break;

    case SNDRV_CTL_ELEM_TYPE_ENUMERATED:
        ev.value.enumerated.item[id] = value;
        break;

    case SNDRV_CTL_ELEM_TYPE_BYTES:
        ev.value.bytes.data[id] = value;
        break;

    default:
        return -EINVAL;
    }

    return ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &ev);
}

static int _mixer_ctl_get_value(struct mixer_ctl *ctl, unsigned int id)
{
    struct snd_ctl_elem_value ev;
    int ret;

    if (!ctl || (id >= ctl->info->count))
        return -EINVAL;

    memset(&ev, 0, sizeof(ev));
    ev.id.numid = ctl->info->id.numid;
    ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_READ, &ev);
    if (ret < 0)
        return ret;

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:
        return !!ev.value.integer.value[id];

    case SNDRV_CTL_ELEM_TYPE_INTEGER:
        return ev.value.integer.value[id];

    case SNDRV_CTL_ELEM_TYPE_ENUMERATED:
        return ev.value.enumerated.item[id];

    case SNDRV_CTL_ELEM_TYPE_BYTES:
        return ev.value.bytes.data[id];

    default:
        return -EINVAL;
    }

    return 0;
}

static int _mixer_ctl_get_percent(struct mixer_ctl *ctl, unsigned int id)
{
    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_INTEGER))
        return -EINVAL;

    return int_to_percent(ctl->info, _mixer_ctl_get_value(ctl, id));
}

static int _mixer_ctl_set_percent(struct mixer_ctl *ctl, unsigned int id, int percent)
{
    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_INTEGER))
        return -EINVAL;

    return _mixer_ctl_set_value(ctl, id, percent_to_int(ctl->info, percent));
}

static int _mixer_ctl_is_access_tlv_rw(struct mixer_ctl *ctl)
{
    return (ctl->info->access & SNDRV_CTL_ELEM_ACCESS_TLV_READWRITE);
}

static int _mixer_ctl_get_array(struct mixer_ctl *ctl, void *array, size_t count)
{
    struct snd_ctl_elem_value ev;
    int ret = 0;
    size_t size;
    void *source;
    size_t total_count;

    if ((!ctl) || !count || !array)
        return -EINVAL;

    total_count = ctl->info->count;

    if ((ctl->info->type == SNDRV_CTL_ELEM_TYPE_BYTES) &&
        _mixer_ctl_is_access_tlv_rw(ctl)) {
            /* Additional two words is for the TLV header */
            total_count += TLV_HEADER_SIZE;
    }

    if (count > total_count)
        return -EINVAL;

    memset(&ev, 0, sizeof(ev));
    ev.id.numid = ctl->info->id.numid;

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:
    case SNDRV_CTL_ELEM_TYPE_INTEGER:
        ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_READ, &ev);
        if (ret < 0)
            return ret;
        size = sizeof(ev.value.integer.value[0]);
        source = ev.value.integer.value;
        break;

    case SNDRV_CTL_ELEM_TYPE_BYTES:
        /* check if this is new bytes TLV */
        if (_mixer_ctl_is_access_tlv_rw(ctl)) {
            struct snd_ctl_tlv *tlv;
            int ret;

            if (count > SIZE_MAX - sizeof(*tlv))
                return -EINVAL;
            tlv = (struct snd_ctl_tlv *)calloc(1, sizeof(*tlv) + count);
            if (!tlv)
                return -ENOMEM;
            tlv->numid = ctl->info->id.numid;
            tlv->length = count;
            ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_TLV_READ, tlv);

            source = tlv->tlv;
            memcpy(array, source, count);

            free(tlv);

            return ret;
        } else {
            ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_READ, &ev);
            if (ret < 0)
                return ret;
            size = sizeof(ev.value.bytes.data[0]);
            source = ev.value.bytes.data;
            break;
        }

    case SNDRV_CTL_ELEM_TYPE_IEC958:
        size = sizeof(ev.value.iec958);
        source = &ev.value.iec958;
        break;

    default:
        return -EINVAL;
    }

    memcpy(array, source, size * count);

    return 0;
}

static int _mixer_ctl_set_array(struct mixer_ctl *ctl, const void *array, size_t count)
{
    struct snd_ctl_elem_value ev;
    size_t size;
    void *dest;
    size_t total_count;

    if ((!ctl) || !count || !array)
        return -EINVAL;

    total_count = ctl->info->count;

    if ((ctl->info->type == SNDRV_CTL_ELEM_TYPE_BYTES) &&
        _mixer_ctl_is_access_tlv_rw(ctl)) {
            /* Additional two words is for the TLV header */
            total_count += TLV_HEADER_SIZE;
    }

    if (count > total_count)
        return -EINVAL;

    memset(&ev, 0, sizeof(ev));
    ev.id.numid = ctl->info->id.numid;

    switch (ctl->info->type) {
    case SNDRV_CTL_ELEM_TYPE_BOOLEAN:
    case SNDRV_CTL_ELEM_TYPE_INTEGER:
        size = sizeof(ev.value.integer.value[0]);
        dest = ev.value.integer.value;
        break;

    case SNDRV_CTL_ELEM_TYPE_BYTES:
        /* check if this is new bytes TLV */
        if (_mixer_ctl_is_access_tlv_rw(ctl)) {
            struct snd_ctl_tlv *tlv;
            int ret = 0;
            if (count > SIZE_MAX - sizeof(*tlv))
                return -EINVAL;
            tlv = (struct snd_ctl_tlv *)calloc(1, sizeof(*tlv) + count);
            if (!tlv)
                return -ENOMEM;
            tlv->numid = ctl->info->id.numid;
            tlv->length = count;
            memcpy(tlv->tlv, array, count);

            ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_TLV_WRITE, tlv);
            free(tlv);

            return ret;
        } else {
            size = sizeof(ev.value.bytes.data[0]);
            dest = ev.value.bytes.data;
        }
        break;

    case SNDRV_CTL_ELEM_TYPE_IEC958:
        size = sizeof(ev.value.iec958);
        dest = &ev.value.iec958;
        break;

    default:
        return -EINVAL;
    }

    memcpy(dest, array, size * count);

    return ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &ev);
}

static int _mixer_ctl_get_range_min(struct mixer_ctl *ctl)
{
    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_INTEGER))
        return -EINVAL;

    return ctl->info->value.integer.min;
}

static int _mixer_ctl_get_range_max(struct mixer_ctl *ctl)
{
    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_INTEGER))
        return -EINVAL;

    return ctl->info->value.integer.max;
}

static unsigned int _mixer_ctl_get_num_enums(struct mixer_ctl *ctl)
{
    if (!ctl)
        return 0;

    return ctl->info->value.enumerated.items;
}

static const char *_mixer_ctl_get_enum_string(struct mixer_ctl *ctl,
                                      unsigned int enum_id)
{
    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_ENUMERATED) ||
        (enum_id >= ctl->info->value.enumerated.items))
        return NULL;

    return (const char *)ctl->ename[enum_id];
}

static int _mixer_ctl_set_enum_by_string(struct mixer_ctl *ctl, const char *string)
{
    unsigned int i, num_enums;
    struct snd_ctl_elem_value ev;
    int ret;

    if (!ctl || (ctl->info->type != SNDRV_CTL_ELEM_TYPE_ENUMERATED))
        return -EINVAL;

    num_enums = ctl->info->value.enumerated.items;
    for (i = 0; i < num_enums; i++) {
        if (!strcmp(string, ctl->ename[i])) {
            memset(&ev, 0, sizeof(ev));
            ev.value.enumerated.item[0] = i;
            ev.id.numid = ctl->info->id.numid;
            ret = ioctl(ctl->mixer->fd, SNDRV_CTL_IOCTL_ELEM_WRITE, &ev);
            if (ret < 0)
                return ret;
            return 0;
        }
    }

    return -EINVAL;
}

static int aml_audio_mixer_int(const char *control, int value, bool set)
{
    int ret = -1;
    struct mixer_ctl *pCtrl = NULL;
    struct mixer *mixer = NULL;
    if (control == NULL) {
        ALOGE("[%s:%d] control is invalid!\n", __FUNCTION__, __LINE__);
        return ret;
    }
    mixer = _mixer_open(DEFAULT_AML_SOUND_CARD);

    if (mixer == NULL) {
        ALOGE("[%s:%d] mixer is invalid!\n", __FUNCTION__, __LINE__);
        return ret;
    }

    pCtrl = _mixer_get_ctl_by_name(mixer, control);
    if (pCtrl == NULL) {
        ALOGE("[%s:%d] Failed to find control: %s\n", __FUNCTION__, __LINE__, control);
        _mixer_close(mixer);
        return ret;
    }
    if (set) {
        ret = _mixer_ctl_set_value(pCtrl, 0, value);
        ALOGV("[%s:%d] set %s: %d, ret %d", __FUNCTION__, __LINE__, control, value, ret);
    } else {
        ret = _mixer_ctl_get_value(pCtrl, 0);
    }
    _mixer_close(mixer);

    return ret;
}

static int aml_audio_mixer_array(const char *control, void *array, size_t count, bool set)
{
    int ret = -1;
    struct mixer_ctl *pCtrl = NULL;
    struct mixer *mixer = NULL;
    if (control == NULL) {
        ALOGE("[%s:%d] control is invalid!\n", __FUNCTION__, __LINE__);
        return ret;
    }
    mixer = _mixer_open(DEFAULT_AML_SOUND_CARD);

    if (mixer == NULL) {
        ALOGE("[%s:%d] mixer is invalid!\n", __FUNCTION__, __LINE__);
        return ret;
    }

    pCtrl = _mixer_get_ctl_by_name(mixer, control);
    if (pCtrl == NULL) {
        ALOGE("[%s:%d] Failed to find control: %s\n", __FUNCTION__, __LINE__, control);
        _mixer_close(mixer);
        return ret;
    }
    if (set) {
        ret = _mixer_ctl_set_array(pCtrl, array, count);
        ALOGV("[%s:%d] set %s, ret %d", __FUNCTION__, __LINE__, control, ret);
    } else {
        ret = _mixer_ctl_get_array(pCtrl, array, count);
    }
    _mixer_close(mixer);

    return ret;
}

/* Headphone mute */
static int set_dac_digital_mute(bool mute)
{
    int ret = 0;
    static bool last_mute_state = false;
    static int dac_digital_volume = DAC_DIGITAl_DEFAULT_VOLUME;   // volume range: 0 ~ 255
    int headphone_dac_gain[HEADPHONE_DAC_CHANNEL_NUM] = {dac_digital_volume, dac_digital_volume};

    if (last_mute_state == mute) {
        return ret;
    }
    if (mute) {
        dac_digital_volume = aml_audio_mixer_int(DAC_DIGITAL_VOLUME, 0, false);//get current hp vol
        headphone_dac_gain[0] = headphone_dac_gain[1] = 0;
        ret = aml_audio_mixer_array(DAC_DIGITAL_VOLUME, headphone_dac_gain, HEADPHONE_DAC_CHANNEL_NUM, true);
    } else {
        //headphone_dac_gain[0] = headphone_dac_gain[1] = dac_digital_volume;
        ret = aml_audio_mixer_array(DAC_DIGITAL_VOLUME, headphone_dac_gain, HEADPHONE_DAC_CHANNEL_NUM, true);
    }
    last_mute_state = mute;
    ALOGD("[%s:%d] DAC Digital %smute, dac_digital_volume is %d", __func__, __LINE__, mute?" ":"un", dac_digital_volume);
    return ret;
}

int aml_audio_set_hdmi_param(bool isconnect)
{
    int ret = 0;
    pthread_mutex_lock(&g_volume_lock);
    chip_id = aml_audio_mixer_int(AML_CHIP_ID, 0, false);
    /*s1a use this way to set hdmi status*/
    if (AML_CHIP_ID_S1A == chip_id) {
        ret = aml_audio_mixer_int(HDMI_CON, isconnect, true);
        ALOGD("[%s:%d] isconnect: %d, ret: %d", __func__, __LINE__, isconnect, ret);
    }
    pthread_mutex_unlock(&g_volume_lock);
    return ret;
}

int aml_audio_set_volume(int value)
{
    int ret = 0;
    if (value < 0 || value > 100) {
        ALOGE("[%s:%d]bad volume: %d", __func__, __LINE__, value);
        return -1;
    }

    pthread_mutex_lock(&g_volume_lock);
    chip_id = aml_audio_mixer_int(AML_CHIP_ID, 0, false);
    /*s1a use TDM-A as cvbs/hdmi_tx samesource*/
    if (AML_CHIP_ID_S1A == chip_id)
        ret = aml_audio_mixer_int(TDMA_GAIN, value, true);
    else
        ret = aml_audio_mixer_int(TDMB_GAIN, value, true);

    ALOGD("[%s:%d] chip_id: %d, volume: %d, ret: %d", __func__, __LINE__, chip_id, value, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_get_volume()
{
    pthread_mutex_lock(&g_volume_lock);
    int ret = 0;
    chip_id = aml_audio_mixer_int(AML_CHIP_ID, 0, false);
    if (AML_CHIP_ID_S1A == chip_id)
        ret = aml_audio_mixer_int(TDMA_GAIN, 0, false);
    else
        ret = aml_audio_mixer_int(TDMB_GAIN, 0, false);
    ALOGD("[%s:%d] chip_id: %d, volume: %d", __func__, __LINE__, chip_id, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_set_mute(int port, bool mute)
{
    pthread_mutex_lock(&g_mute_lock);
    int ret = -1;
    if (port <= AUDIO_PORT_MIN || port >= AUDIO_PORT_MAX) {
        ALOGE("[%s:%d]bad port: %d", __func__, __LINE__, port);
    } else if (port == AUDIO_PORT_HDMI) {
        if (aml_audio_get_spdif_format() == AUD_CODEC_TYPE_STEREO_PCM) {
            if (mute && !(aml_audio_get_volume() == 0)) {
                reserved_volume = aml_audio_get_volume();
                ret = aml_audio_set_volume(0);
            } else if (!mute) {
                ret = aml_audio_set_volume(reserved_volume);
            }
        } else {
            ret = aml_audio_mixer_int(HDMI_OUT_MUTE, mute ? 1 : 0, true);
        }
    } else if (port == AUDIO_PORT_HEADPHONE) {
        ret = set_dac_digital_mute(mute);
    }
    ALOGD("[%s:%d] port: %d, mute: %d, ret: %d", __func__, __LINE__, port, mute, ret);
    pthread_mutex_unlock(&g_mute_lock);
    return ret;
}

bool aml_audio_get_mute(int port)
{
    pthread_mutex_lock(&g_mute_lock);
    bool ret = false;
    if (port <= AUDIO_PORT_MIN || port >= AUDIO_PORT_MAX) {
        ALOGE("[%s:%d]bad port: %d", __func__, __LINE__, port);
    } else if (port == AUDIO_PORT_HDMI) {
        if (aml_audio_get_spdif_format() == AUD_CODEC_TYPE_STEREO_PCM) {
            ret = (aml_audio_get_volume() == 0) ? true : false;
        } else {
            ret = aml_audio_mixer_int(HDMI_OUT_MUTE, 0, false) ? true : false;
        }
    } else if (port == AUDIO_PORT_HEADPHONE) {
        ret = aml_audio_mixer_int(DAC_DIGITAL_VOLUME, 0, false) ? false : true;
    }
    ALOGD("[%s:%d] port: %d, mute: %d", __func__, __LINE__, port, ret);
    pthread_mutex_unlock(&g_mute_lock);
    return ret;
}

int aml_audio_set_digital_mode(enum audio_digital_mode mode)
{
    int ret = 0;
    if ((mode != AML_HAL_PCM) && (mode != AML_HAL_DDP) &&
        (mode != AML_HAL_AUTO) && (mode != AML_HAL_BYPASS) &&
        (mode != AML_HAL_DD)) {
        printf("Invalid mode\n");
        return false;
    }

    pthread_mutex_lock(&g_volume_lock);
    ret = aml_audio_mixer_int(DIGITAL_MODE, mode, true);
    ALOGD("[%s:%d] mode: %d, ret: %d", __func__, __LINE__, mode, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_get_digital_mode()
{
    pthread_mutex_lock(&g_volume_lock);
    int ret = 0;
    ret = aml_audio_mixer_int(DIGITAL_MODE, 0, false);
    ALOGD("[%s:%d] mod: %d", __func__, __LINE__, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_set_drc_mode(enum audio_drc_mode mode)
{
    int ret = 0;
    int drc_control = DRC_MODE_LINE;
    if ((mode != DRC_RF) && (mode != DRC_LINE) && (mode != DRC_OFF)) {
        printf("Invalid mode!\n");
        return false;
    }

    pthread_mutex_lock(&g_volume_lock);
    if (mode == DRC_LINE) {
        drc_control = (DRC_MODE_LINE<<DRC_MODE_BIT)|(100<<DRC_HIGH_CUT_BIT)|(100<<DRC_LOW_BST_BIT);
    } else if (mode == DRC_RF) {
        drc_control = (DRC_MODE_RF<<DRC_MODE_BIT)|(100<<DRC_HIGH_CUT_BIT)|(100<<DRC_LOW_BST_BIT);
    }
    ret = aml_audio_mixer_int(DRC_CONTROL, drc_control, true);
    ALOGD("[%s:%d] mode: %d, drc_control: %#x, ret: %d.", __func__, __LINE__, mode, drc_control, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_get_drc_mode()
{
    pthread_mutex_lock(&g_volume_lock);
    int ret = 0, drc_control;
    drc_control = aml_audio_mixer_int(DRC_CONTROL, 0, false);

    if (drc_control == DRC_MODE_LINE)
        ret = DRC_OFF;
    else
        ret = (drc_control&3 == DRC_MODE_LINE) ? DRC_LINE : DRC_RF;
    ALOGD("[%s:%d] mode: %d", __func__, __LINE__, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}

int aml_audio_get_spdif_format()
{
    pthread_mutex_lock(&g_volume_lock);
    int ret = 0;
    ret = aml_audio_mixer_int(SPDIF_FORMAT, 0, false);
    ALOGD("[%s:%d] ret: %x.", __func__, __LINE__, ret);
    pthread_mutex_unlock(&g_volume_lock);

    return ret;
}
}//extern c
