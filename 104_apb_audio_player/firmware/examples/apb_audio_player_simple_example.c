/************************************************************************************************************************
APB-音频播放器示例代码
@brief  播放音乐10s然后停止
@attention 请根据硬件平台更换与延迟(delay)相关的API
@date   2024/08/31
@author 陈家耀
@eidt   2024/08/31 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_audio_player.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_AUDIO_PLAYER_BASEADDR 0x40000000 // APB-音频播放器外设基地址

#define MUSIC_FLASH_BASEADDR 0 // 音乐在flash中的基地址
#define MUSIC_LEN (72 * 22050) // 音乐长度(以字节计)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbAudio audio_player; // 音频播放器外设句柄

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_audio_player_simple_example(void){
	// 初始化音频播放器
	init_apb_audio_player(&audio_player, APB_AUDIO_PLAYER_BASEADDR);
	
	// 设置音频采样率为22.05KHz
	apb_audio_player_set_audio_sample_rate(&audio_player, AUDIO_SAMPLE_RATE_22050);
	
	// 开始播放音乐
	apb_audio_player_start_dma(&audio_player, MUSIC_FLASH_BASEADDR, MUSIC_LEN);
	
	delay_ms(10 * 1000); // 延迟10s
	
	__APB_AUDIO_PLAYER_ABORT_DMA(&audio_player); // 停止播放音乐
	
	while(1);
}
