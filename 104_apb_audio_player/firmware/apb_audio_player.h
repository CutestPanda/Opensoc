#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ��Ƶ����������
#define AUDIO_SAMPLE_RATE_8000 0
#define AUDIO_SAMPLE_RATE_11025 1
#define AUDIO_SAMPLE_RATE_22050 2
#define AUDIO_SAMPLE_RATE_24000 3
#define AUDIO_SAMPLE_RATE_32000 4
#define AUDIO_SAMPLE_RATE_44100 5
#define AUDIO_SAMPLE_RATE_47250 6
#define AUDIO_SAMPLE_RATE_48000 7

// ������������
#define ERR_SPI_TX_FIFO_WT_OVF_MASK 0x01 // SPI����������fifoд���
#define ERR_SPI_RX_FIFO_WT_OVF_MASK 0x02 // SPI����������fifoд���

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_AUDIO_H
#define __APB_AUDIO_H

typedef struct{
	uint32_t flash_rd_baseaddr; // ��Ƶ��flash�еĻ���ַ
	uint32_t flash_rd_bytes_n; // ��Ƶ�ֽ���
	uint32_t sample_rate; // ��Ƶ����������
	uint32_t flash_dma_cs; // flash-dma����
	uint32_t err_flag_vec; // �����־����
}ApbAudioHd;

typedef struct{
	ApbAudioHd* hardware; // APB-��Ƶ�������Ĵ����ӿ�(�ṹ��ָ��)
}ApbAudio;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ��ֹ������Ƶ
#define __APB_AUDIO_PLAYER_ABORT_DMA(audio_player) ((audio_player)->hardware->flash_dma_cs = 0x00000004)

// �ж�flash-dma�Ƿ����
#define __IS_APB_AUDIO_PLAYER_IDLE(audio_player) ((audio_player)->hardware->flash_dma_cs & 0x00000001)

// ��ȡ�����־����
#define __APB_AUDIO_PLAYER_GET_ERR_FLAG(audio_player) ((audio_player)->hardware->err_flag_vec)
// ��������־����
#define __APB_AUDIO_PLAYER_CLC_ERR_FLAG(audio_player) ((audio_player)->hardware->err_flag_vec = 0x00000000)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_apb_audio_player(ApbAudio* audio_player, uint32_t baseaddr); // ��ʼ��APB-��Ƶ������

void apb_audio_player_set_audio_sample_rate(ApbAudio* audio_player, uint8_t audio_sample_rate); // ������Ƶ������

int apb_audio_player_start_dma(ApbAudio* audio_player, 
	uint32_t flash_rd_baseaddr, uint32_t flash_rd_bytes_n); // ��ʼ����һ����Ƶ
