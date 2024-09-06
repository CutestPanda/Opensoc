/************************************************************************************************************************
APB-��Ƶ������ʾ������
@brief  ��������10sȻ��ֹͣ
@attention �����Ӳ��ƽ̨�������ӳ�(delay)��ص�API
@date   2024/08/31
@author �¼�ҫ
@eidt   2024/08/31 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_audio_player.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_AUDIO_PLAYER_BASEADDR 0x40000000 // APB-��Ƶ�������������ַ

#define MUSIC_FLASH_BASEADDR 0 // ������flash�еĻ���ַ
#define MUSIC_LEN (72 * 22050) // ���ֳ���(���ֽڼ�)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbAudio audio_player; // ��Ƶ������������

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_audio_player_simple_example(void){
	// ��ʼ����Ƶ������
	init_apb_audio_player(&audio_player, APB_AUDIO_PLAYER_BASEADDR);
	
	// ������Ƶ������Ϊ22.05KHz
	apb_audio_player_set_audio_sample_rate(&audio_player, AUDIO_SAMPLE_RATE_22050);
	
	// ��ʼ��������
	apb_audio_player_start_dma(&audio_player, MUSIC_FLASH_BASEADDR, MUSIC_LEN);
	
	delay_ms(10 * 1000); // �ӳ�10s
	
	__APB_AUDIO_PLAYER_ABORT_DMA(&audio_player); // ֹͣ��������
	
	while(1);
}
