#ifndef __AUDIO_EFFECT_PARAMS_H_
#define __AUDIO_EFFECT_PARAMS_H_

#include <hardware/hardware.h>
#include <hardware/audio.h>

#ifdef __cplusplus
extern "C"
{
#endif

//-----------Balance typedef-------------------------------
//Warning:balance is used for 51 bands

#define BALANCE_MAX_BANDS 51

#define BITS    16
#define MAXbit  (1 << (BITS - 1))
#define INT2FLOAT(a) ((float)a / MAXbit)
#define FLOAT2INT(a) (int)((float)a * MAXbit)

typedef enum {
    BALANCE_PARAM_LEVEL = 0,
    BALANCE_PARAM_ENABLE,
    BALANCE_PARAM_LEVEL_NUM,
    BALANCE_PARAM_INDEX,
} Balanceparams;

typedef struct aml_balance_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        int32_t v;
        float f;
        float index[BALANCE_MAX_BANDS];
    };
} aml_balance_param_t;

//-------------VirtualSurround typedef--------------------------
typedef enum {
    VIRTUALSURROUND_PARAM_ENABLE,
    VIRTUALSURROUND_PARAM_EFFECTLEVEL,
} Virtualsurroundparams;

typedef struct aml_virtualsurround_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        int32_t v;
        float f;
    };
} aml_virtualsurround_param_t;

//-------------TrebleBass typedef--------------------------
typedef enum {
    TREBASS_PARAM_INVALID = -1,
    TREBASS_PARAM_BASS_LEVEL,
    TREBASS_PARAM_TREBLE_LEVEL,
    TREBASS_PARAM_ENABLE,
} TREBASSparams;

typedef struct aml_treblebass_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        uint32_t v;
        float f;
    };
} aml_treblebass_param_t;

//-------------Hpeq typedef--------------------------
typedef enum {
    HPEQ_PARAM_INVALID = -1,
    HPEQ_PARAM_ENABLE,
    HPEQ_PARAM_EFFECT_MODE,
    HPEQ_PARAM_EFFECT_CUSTOM,
} HPEQparams;

typedef struct aml_hpeq_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        uint32_t v;
        float f;
        signed char band[5];
    };
} aml_hpeq_param_t;

//-------------Avl typedef--------------------------
typedef enum {
    AVL_PARAM_ENABLE,
    AVL_PARAM_PEAK_LEVEL,
    AVL_PARAM_DYNAMIC_THRESHOLD,
    AVL_PARAM_NOISE_THRESHOLD,
    AVL_PARAM_RESPONSE_TIME,
    AVL_PARAM_RELEASE_TIME,
    AVL_PARAM_SOURCE_IN,
} Avlparams;

typedef struct aml_avl_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        int32_t v;
        float f;
    };
} aml_avl_param_t;

#define VX_MAX_PARAM_SIZE 32
typedef enum {
    /*Tuning interface*/
    DTS_PARAM_MBHL_ENABLE_I32 = 0,
    DTS_PARAM_MBHL_BYPASS_GAIN_I32 = 1,
    DTS_PARAM_MBHL_REFERENCE_LEVEL_I32 = 2,
    DTS_PARAM_MBHL_VOLUME_I32 = 3,
    DTS_PARAM_MBHL_VOLUME_STEP_I32 = 4,
    DTS_PARAM_MBHL_BALANCE_STEP_I32 = 5,
    DTS_PARAM_MBHL_OUTPUT_GAIN_I32 = 6,
    DTS_PARAM_MBHL_MODE_I32 = 7,
    DTS_PARAM_MBHL_PROCESS_DISCARD_I32 = 8,
    DTS_PARAM_MBHL_CROSS_LOW_I32 = 9,
    DTS_PARAM_MBHL_CROSS_MID_I32 = 10,
    DTS_PARAM_MBHL_COMP_ATTACK_I32 = 11,
    DTS_PARAM_MBHL_COMP_LOW_RELEASE_I32 = 12,
    DTS_PARAM_MBHL_COMP_LOW_RATIO_I32 = 13,
    DTS_PARAM_MBHL_COMP_LOW_THRESH_I32 = 14,
    DTS_PARAM_MBHL_COMP_LOW_MAKEUP_I32 = 15,
    DTS_PARAM_MBHL_COMP_MID_RELEASE_I32 = 16,
    DTS_PARAM_MBHL_COMP_MID_RATIO_I32 = 17,
    DTS_PARAM_MBHL_COMP_MID_THRESH_I32 = 18,
    DTS_PARAM_MBHL_COMP_MID_MAKEUP_I32 = 19,
    DTS_PARAM_MBHL_COMP_HIGH_RELEASE_I32 = 20,
    DTS_PARAM_MBHL_COMP_HIGH_RATIO_I32 = 21,
    DTS_PARAM_MBHL_COMP_HIGH_THRESH_I32 = 22,
    DTS_PARAM_MBHL_COMP_HIGH_MAKEUP_I32 = 23,
    DTS_PARAM_MBHL_BOOST_I32 = 24,
    DTS_PARAM_MBHL_THRESHOLD_I32 = 25,
    DTS_PARAM_MBHL_SLOW_OFFSET_I32 = 26,
    DTS_PARAM_MBHL_FAST_ATTACK_I32 = 27,
    DTS_PARAM_MBHL_FAST_RELEASE_I32 = 28,
    DTS_PARAM_MBHL_SLOW_ATTACK_I32 = 29,
    DTS_PARAM_MBHL_SLOW_RELEASE_I32 = 30,
    DTS_PARAM_MBHL_DELAY_I32 = 31,
    DTS_PARAM_MBHL_ENVELOPE_FREQUENCY_I32 = 32,
    DTS_PARAM_MBHL_APP_FRT_LOWCROSS_F32 = 33,
    DTS_PARAM_MBHL_APP_FRT_MIDCROSS_F32 = 34,
    DTS_PARAM_TBHDX_ENABLE_I32 = 35,
    DTS_PARAM_TBHDX_MONO_MODE_I32 = 36,
    DTS_PARAM_TBHDX_MAXGAIN_I32 = 37,
    DTS_PARAM_TBHDX_SPKSIZE_I32 = 38,
    DTS_PARAM_TBHDX_HP_ENABLE_I32 = 39,
    DTS_PARAM_TBHDX_TEMP_GAIN_I32 = 40,
    DTS_PARAM_TBHDX_PROCESS_DISCARD_I32 = 41,
    DTS_PARAM_TBHDX_HPORDER_I32 = 42,
    DTS_PARAM_TBHDX_APP_SPKSIZE_I32 = 43,
    DTS_PARAM_TBHDX_APP_HPRATIO_F32 = 44,
    DTS_PARAM_TBHDX_APP_EXTBASS_F32 = 45,
    DTS_PARAM_VX_ENABLE_I32 = 46,
    DTS_PARAM_VX_INPUT_MODE_I32 = 47,
    DTS_PARAM_VX_OUTPUT_MODE_I32 = 48,
    DTS_PARAM_VX_HEADROOM_GAIN_I32 = 49,
    DTS_PARAM_VX_PROC_OUTPUT_GAIN_I32 = 50,
    DTS_PARAM_VX_REFERENCE_LEVEL_I32 = 51,
    DTS_PARAM_TSX_ENABLE_I32 = 52,
    DTS_PARAM_TSX_PASSIVEMATRIXUPMIX_ENABLE_I32 = 53,
    DTS_PARAM_TSX_HEIGHT_UPMIX_ENABLE_I32 = 54,
    DTS_PARAM_TSX_LPR_GAIN_I32 = 55,
    DTS_PARAM_TSX_CENTER_GAIN_I32 = 56,
    DTS_PARAM_TSX_HORIZ_VIR_EFF_CTRL_I32 = 57,
    DTS_PARAM_TSX_HEIGHTMIX_COEFF_I32 = 58,
    DTS_PARAM_TSX_PROCESS_DISCARD_I32 = 59,
    DTS_PARAM_TSX_HEIGHT_DISCARD_I32 = 60,
    DTS_PARAM_TSX_FRNT_CTRL_I32 = 61,
    DTS_PARAM_TSX_SRND_CTRL_I32 = 62,
    DTS_PARAM_VX_DC_ENABLE_I32 = 63,
    DTS_PARAM_VX_DC_CONTROL_I32 = 64,
    DTS_PARAM_VX_DEF_ENABLE_I32 = 65,
    DTS_PARAM_VX_DEF_CONTROL_I32 = 66,
    DTS_PARAM_LOUDNESS_CONTROL_ENABLE_I32 = 67,
    DTS_PARAM_LOUDNESS_CONTROL_TARGET_LOUDNESS_I32 = 68,
    DTS_PARAM_LOUDNESS_CONTROL_PRESET_I32 = 69,
    DTS_PARAM_LOUDNESS_CONTROL_IO_MODE_I32 = 70,
    DTS_PARAM_AEQ_ENABLE_I32 = 71,
    DTS_PARAM_AEQ_DISCARD_I32 = 72,
    DTS_PARAM_AEQ_INPUT_GAIN_I16 = 73,
    DTS_PARAM_AEQ_OUTPUT_GAIN_I16 = 74,
    DTS_PARAM_AEQ_BYPASS_GAIN_I16 = 75,
    DTS_PARAM_AEQ_LR_LINK_I32 = 76,
    DTS_PARAM_AEQ_BAND_Fre = 77,
    DTS_PARAM_AEQ_BAND_Gain = 78,
    DTS_PARAM_AEQ_BAND_Q = 79,
    DTS_PARAM_AEQ_BAND_type = 80,
    DTS_PARAM_CHANNEL_NUM = 81,

    /*UI interface*/
    VIRTUALX_PARAM_ENABLE = 82,
    VIRTUALX_PARAM_DIALOGCLARITY_MODE = 83,
    VIRTUALX_PARAM_SURROUND_MODE = 84,
    AUDIO_DTS_PARAM_TYPE_NONE = 85,
    AUDIO_DTS_PARAM_TYPE_TRU_SURROUND = 86,
    AUDIO_DTS_PARAM_TYPE_CC3D = 87,
    AUDIO_DTS_PARAM_TYPE_TRU_BASS = 88,
    AUDIO_DTS_PARAM_TYPE_TRU_DIALOG = 89,
    AUDIO_DTS_PARAM_TYPE_DEFINITION = 90,
    AUDIO_DTS_PARAM_TYPE_TRU_VOLUME = 91,
    /* debug interface */
    AUDIO_DTS_ALL_PARAM_DUMP = 92,
} Virtualx_params;
typedef struct Virtualx_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        int32_t v;
        float f;
        float params[VX_MAX_PARAM_SIZE];
    };
} Virtualx_param_t;


//-------------DBX typedef--------------------------
typedef enum {
    DBX_PARAM_ENABLE = 0,
    DBX_SET_MODE     = 1,
    DBX_Read_Param    = 2,
    DBX_Write_Param   = 3,
    DBX_Read_Coeff    = 4,
    DBX_Write_Coeff   = 5,
    DBX_Write_VCF     = 6,
    DBX_Mute         = 7,
    DBX_Version      = 8,
} DBXparams;

typedef struct aml_dbx_param_s {
    effect_param_t param;
    uint32_t command;
    union {
        int32_t v;
        int32_t value[2];//index & value
    };
} aml_dbx_param_t;
#ifdef __cplusplus
}
#endif

#endif /* __AUDIO_EFFECT_PARAMS_H_ */