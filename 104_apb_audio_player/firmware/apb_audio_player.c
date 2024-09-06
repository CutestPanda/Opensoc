/************************************************************************************************************************
APB-音频播放器驱动(主源文件)
@brief  APB-音频播放器
@date   2024/08/23
@author 陈家耀
@eidt   2024/08/23 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "apb_audio_player.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化APB-音频播放器
@param  audio_player APB-音频播放器(结构体指针)
        base_addr APB-音频播放器外设基地址
@return none
*************************/
void init_apb_audio_player(ApbAudio* audio_player, uint32_t baseaddr){
	audio_player->hardware = (ApbAudioHd*)baseaddr;
}

/*************************
@cfg
@public
@brief  设置音频采样率
@param  audio_player APB-音频播放器(结构体指针)
        audio_sample_rate 音频采样率类型
@return none
*************************/
void apb_audio_player_set_audio_sample_rate(ApbAudio* audio_player, uint8_t audio_sample_rate){
	audio_player->hardware->sample_rate = (uint32_t)audio_sample_rate;
}

/*************************
@io
@public
@brief  启动flash-dma, 开始播放一段音频
@param  audio_player APB-音频播放器(结构体指针)
        flash_rd_baseaddr 音频在flash中的基地址
			  flash_rd_bytes_n 音频字节数
@return 是否成功
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
