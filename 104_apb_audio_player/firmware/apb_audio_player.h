#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 音频采样率类型
#define AUDIO_SAMPLE_RATE_8000 0
#define AUDIO_SAMPLE_RATE_11025 1
#define AUDIO_SAMPLE_RATE_22050 2
#define AUDIO_SAMPLE_RATE_24000 3
#define AUDIO_SAMPLE_RATE_32000 4
#define AUDIO_SAMPLE_RATE_44100 5
#define AUDIO_SAMPLE_RATE_47250 6
#define AUDIO_SAMPLE_RATE_48000 7

// 错误类型掩码
#define ERR_SPI_TX_FIFO_WT_OVF_MASK 0x01 // SPI控制器发送fifo写溢出
#define ERR_SPI_RX_FIFO_WT_OVF_MASK 0x02 // SPI控制器接收fifo写溢出

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_AUDIO_H
#define __APB_AUDIO_H

typedef struct{
	uint32_t flash_rd_baseaddr; // 音频在flash中的基地址
	uint32_t flash_rd_bytes_n; // 音频字节数
	uint32_t sample_rate; // 音频采样率类型
	uint32_t flash_dma_cs; // flash-dma控制
	uint32_t err_flag_vec; // 错误标志向量
}ApbAudioHd;

typedef struct{
	ApbAudioHd* hardware; // APB-音频播放器寄存器接口(结构体指针)
}ApbAudio;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中止播放音频
#define __APB_AUDIO_PLAYER_ABORT_DMA(audio_player) ((audio_player)->hardware->flash_dma_cs = 0x00000004)

// 判断flash-dma是否空闲
#define __IS_APB_AUDIO_PLAYER_IDLE(audio_player) ((audio_player)->hardware->flash_dma_cs & 0x00000001)

// 获取错误标志向量
#define __APB_AUDIO_PLAYER_GET_ERR_FLAG(audio_player) ((audio_player)->hardware->err_flag_vec)
// 清除错误标志向量
#define __APB_AUDIO_PLAYER_CLC_ERR_FLAG(audio_player) ((audio_player)->hardware->err_flag_vec = 0x00000000)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_apb_audio_player(ApbAudio* audio_player, uint32_t baseaddr); // 初始化APB-音频播放器

void apb_audio_player_set_audio_sample_rate(ApbAudio* audio_player, uint8_t audio_sample_rate); // 设置音频采样率

int apb_audio_player_start_dma(ApbAudio* audio_player, 
	uint32_t flash_rd_baseaddr, uint32_t flash_rd_bytes_n); // 开始播放一段音频
