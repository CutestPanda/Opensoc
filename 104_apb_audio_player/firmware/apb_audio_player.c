/************************************************************************************************************************
APB-��Ƶ����������(��Դ�ļ�)
@brief  APB-��Ƶ������
@date   2024/08/23
@author �¼�ҫ
@eidt   2024/08/23 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "apb_audio_player.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��APB-��Ƶ������
@param  audio_player APB-��Ƶ������(�ṹ��ָ��)
        base_addr APB-��Ƶ�������������ַ
@return none
*************************/
void init_apb_audio_player(ApbAudio* audio_player, uint32_t baseaddr){
	audio_player->hardware = (ApbAudioHd*)baseaddr;
}

/*************************
@cfg
@public
@brief  ������Ƶ������
@param  audio_player APB-��Ƶ������(�ṹ��ָ��)
        audio_sample_rate ��Ƶ����������
@return none
*************************/
void apb_audio_player_set_audio_sample_rate(ApbAudio* audio_player, uint8_t audio_sample_rate){
	audio_player->hardware->sample_rate = (uint32_t)audio_sample_rate;
}

/*************************
@io
@public
@brief  ����flash-dma, ��ʼ����һ����Ƶ
@param  audio_player APB-��Ƶ������(�ṹ��ָ��)
        flash_rd_baseaddr ��Ƶ��flash�еĻ���ַ
			  flash_rd_bytes_n ��Ƶ�ֽ���
@return �Ƿ�ɹ�
*************************/
int apb_audio_player_start_dma(ApbAudio* audio_player, uint32_t flash_rd_baseaddr, uint32_t flash_rd_bytes_n){
	if(!(audio_player->hardware->flash_dma_cs & 0x00000001)){
		return -1;
	}else{
		audio_player->hardware->flash_rd_baseaddr = flash_rd_baseaddr;
		audio_player->hardware->flash_rd_bytes_n = flash_rd_bytes_n;
		audio_player->hardware->flash_dma_cs = 0x00000002;
		
		return 0;
	}
}
