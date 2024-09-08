/************************************************************************************************************************
SD卡控制器驱动(主源文件)
@brief  SD卡控制器驱动
@date   2024/09/07
@author 陈家耀
@eidt    2024/09/07 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "sd_card.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define INIT_ACMD41_N 20 // 初始化时发送ACMD41命令的尝试次数
#define INIT_DIV_RATE 199 // 初始化时的分频系数
// 对于SD卡写, 运行时的分频系数必须>=1???
#define RUNNING_DIV_RATE 1 // 运行时的分频系数

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 命令号
#define SD_CARD_CMD0 0
#define SD_CARD_CMD8 8
#define SD_CARD_CMD55 55
#define SD_CARD_CMD41 41
#define SD_CARD_CMD2 2
#define SD_CARD_CMD3 3
#define SD_CARD_CMD16 16
#define SD_CARD_CMD7 7
#define SD_CARD_CMD6 6
#define SD_CARD_CMD17 17
#define SD_CARD_CMD18 18
#define SD_CARD_CMD24 24
#define SD_CARD_CMD25 25
#define SD_CARD_CMD12 12

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化SD卡
@param  sdio APB-SDIO(结构体指针)
        en_wide_sdio 是否使用4位SDIO总线
				init_res SD卡初始化结果(结构体指针)
				baseaddr APB-SDIO外设基地址
@return 是否成功
*************************/
int sd_card_init(ApbSDIO* sdio, uint8_t en_wide_sdio, SDCardInitRes* init_res, uint32_t baseaddr){
	ApbSDIOResp sdio_resp;
	
	apb_sdio_set_div_rate(sdio, INIT_DIV_RATE); // 设置SDIO时钟分频数
	apb_sdio_set_en_wide_sdio(sdio, en_wide_sdio); // 设置SDIO总线位宽
	apb_sdio_set_en_clk(sdio, 1); // 启动SDIO时钟
	
	delay_ms(100);
	
	// 发送CMD0复位
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD0, 0x00000000, 0));
	
	// 发送CMD8鉴别SD1.X和SD2.0
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD8, 0x000001AA, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.crc_err){
		return SD_CARD_INIT_CMD8_ERR;
	}else{
		init_res->sd2_supported = !sdio_resp.is_timeout;
	}
	
	// 发送ACMD41
	for(int i = 0;i < INIT_ACMD41_N;i++){
		// CMD55
		while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD55, 0x00000000, 0));
		delay_ms(10);
		while(!__apb_sdio_is_ctrler_idle(sdio));
		apb_sdio_get_resp(sdio, &sdio_resp);
		if(sdio_resp.is_timeout || sdio_resp.crc_err){
			return SD_CARD_INIT_ACMD41_ERR;
		}
		// CMD41
		while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD41, 0x50FF8000, 0));
		delay_ms(10);
		while(!__apb_sdio_is_ctrler_idle(sdio));
		apb_sdio_get_resp(sdio, &sdio_resp);
		if(sdio_resp.is_timeout || sdio_resp.crc_err){
			return SD_CARD_INIT_ACMD41_ERR;
		}
		if(sdio_resp.resp_content[1] & 0x00000080){
			init_res->large_volume = (sdio_resp.resp_content[1] & 0x00000040) ? 1:0;
			
			break;
		}else if(i == INIT_ACMD41_N - 1){
			return SD_CARD_INIT_POWER_UP_FAILED;
		}
	}
	
	// 发送CMD2以获取CID
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD2, 0x00000000, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD2_ERR;
	}
	
	// 发送CMD3要求card指定一个RCA
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD3, 0x00000000, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD3_ERR;
	}
	init_res->rca = ((uint16_t)(sdio_resp.resp_content[0] >> 16)) | ((uint16_t)(sdio_resp.resp_content[1] << 8));
	
	// 发送CMD7选中卡
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD7, (((uint32_t)init_res->rca) << 16), 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD7_ERR;
	}
	
	// 发送CMD16指定块大小为512Byte
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD16, 0x00000200, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD16_ERR;
	}
	// 检查SD卡是否处于Transfer状态
	if(((sdio_resp.resp_content[0] >> 9) & 0x0F) != 4){
		return SD_CARD_INIT_NOT_TRANSFER;
	}
	
	// 发送ACMD6设置总线位宽
	// CMD55
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD55, (((uint32_t)init_res->rca) << 16), 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_ACMD6_ERR;
	}
	// CMD6
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD6, en_wide_sdio ? 0x00000002:0x00000000, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_ACMD6_ERR;
	}
	
	// 发送CMD6查询SD卡功能
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD6, 0x00FF0001, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD6_ERR;
	}
	
	uint32_t cmd6_rbuf[128];
	
	if(sd_card_read_data_block(sdio, cmd6_rbuf) != 128){
		return SD_CARD_INIT_CMD6_ERR;
	}
	
	// 发送CMD6切换到高速模式
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD6, 0x80FF0001, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD6_ERR;
	}
	
	if(sd_card_read_data_block(sdio, cmd6_rbuf) != 128){
		return SD_CARD_INIT_CMD6_ERR;
	}
	
	apb_sdio_set_div_rate(sdio, RUNNING_DIV_RATE); // 初始化完成, 重新设置SDIO时钟分频数
	
	return SD_CARD_INIT_SUCCESS;
}

/*************************
@io
@public
@brief  发送单块读命令
@param  sdio APB-SDIO(结构体指针)
        addr 块地址
@return 是否成功
*************************/
int sd_card_send_read_single_block_cmd(ApbSDIO* sdio, uint32_t addr){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD17, addr, 0);
}

/*************************
@io
@public
@brief  发送多块读命令
@param  sdio APB-SDIO(结构体指针)
        addr 块基地址
        read_n 读取块数
@return 是否成功
*************************/
int sd_card_send_read_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t read_n){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD18, addr, read_n);
}

/*************************
@io
@public
@brief  从缓冲区读取数据
@param  sdio APB-SDIO(结构体指针)
        rdata 读数据缓冲区基地址
@return 读取到的双字数
*************************/
uint32_t sd_card_read_data_block(ApbSDIO* sdio, uint32_t* rdata){
	uint32_t read_data_n = 0;

	while(!apb_sdio_read_data(sdio, rdata + read_data_n)){
		read_data_n++;
	}
	
	return read_data_n;
}

/*************************
@io
@public
@brief  发送单块写命令
@param  sdio APB-SDIO(结构体指针)
        addr 块地址
@return 是否成功
*************************/
int sd_card_send_write_single_block_cmd(ApbSDIO* sdio, uint32_t addr){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD24, addr, 0);
}

/*************************
@io
@public
@brief  发送多块写命令
@param  sdio APB-SDIO(结构体指针)
        addr 块地址
				write_n 写入块数
@return 是否成功
*************************/
int sd_card_send_write_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t write_n){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD25, addr, write_n);
}

/*************************
@io
@public
@brief  向缓冲区写入数据
@param  sdio APB-SDIO(结构体指针)
        wdata 写数据基地址
				len 待写数据的双字数
@return none
*************************/
void sd_card_write_data_block(ApbSDIO* sdio, uint32_t* wdata, uint32_t len){
	for(int i = 0;i < len;i++){
		while(apb_sdio_wt_data(sdio, wdata[i]));
	}
}

/*************************
@io
@public
@brief  发送停止传输命令
@param  sdio APB-SDIO(结构体指针)
@attention 本函数应在每个多块读/写命令后调用
@return 是否成功
*************************/
int sd_card_stop_trans(ApbSDIO* sdio){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD12, 0x00000000, 0);
}
