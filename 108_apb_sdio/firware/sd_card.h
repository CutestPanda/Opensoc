/************************************************************************************************************************
SD卡控制器驱动(接口头文件)
@brief  SD卡控制器驱动
@date   2024/09/07
@author 陈家耀
************************************************************************************************************************/

#include "apb_sdio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 初始化结果
#define SD_CARD_INIT_CMD8_ERR -1 // CMD8错误
#define SD_CARD_INIT_ACMD41_ERR -2 // ACMD41错误
#define SD_CARD_INIT_POWER_UP_FAILED -3 // 上电失败
#define SD_CARD_INIT_CMD2_ERR -4 // CMD2错误
#define SD_CARD_INIT_CMD3_ERR -5 // CMD3错误
#define SD_CARD_INIT_CMD7_ERR -6 // CMD7错误
#define SD_CARD_INIT_CMD16_ERR -7 // CMD16错误
#define SD_CARD_INIT_NOT_TRANSFER -8 // 未进入Transfer状态
#define SD_CARD_INIT_ACMD6_ERR -9 // ACMD6错误
#define SD_CARD_INIT_CMD6_ERR -10 // CMD6错误
#define SD_CARD_INIT_SUCCESS 0 // 成功

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __SD_CARD_H
#define __SD_CARD_H

typedef struct{
	uint8_t sd2_supported; // 是否支持SD2.0
	uint8_t large_volume; // 是否大容量卡
	uint16_t rca; // 卡推荐地址(RCA)
}SDCardInitRes;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 初始化SD卡
int sd_card_init(ApbSDIO* sdio, uint8_t en_wide_sdio, SDCardInitRes* init_res, uint32_t baseaddr);

// 发送单块读命令
int sd_card_send_read_single_block_cmd(ApbSDIO* sdio, uint32_t addr);
// 发送多块读命令
int sd_card_send_read_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t read_n);
// 从缓冲区读取数据
uint32_t sd_card_read_data_block(ApbSDIO* sdio, uint32_t* rdata);

// 发送单块写命令
int sd_card_send_write_single_block_cmd(ApbSDIO* sdio, uint32_t addr);
// 发送多块写命令
int sd_card_send_write_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t write_n);
// 向缓冲区写入数据
void sd_card_write_data_block(ApbSDIO* sdio, uint32_t* wdata, uint32_t len);

// 发送停止传输命令
int sd_card_stop_trans(ApbSDIO* sdio);
