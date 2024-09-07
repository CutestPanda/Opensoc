/************************************************************************************************************************
SD������������(��Դ�ļ�)
@brief  SD������������
@date   2024/09/07
@author �¼�ҫ
@eidt    2024/09/07 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "sd_card.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define INIT_ACMD41_N 20 // ��ʼ��ʱ����ACMD41����ĳ��Դ���
#define INIT_DIV_RATE 199 // ��ʼ��ʱ�ķ�Ƶϵ��
// ����SD��д, ����ʱ�ķ�Ƶϵ������>=1???
#define RUNNING_DIV_RATE 1 // ����ʱ�ķ�Ƶϵ��

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �����
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
@brief  ��ʼ��SD��
@param  sdio APB-SDIO(�ṹ��ָ��)
        en_wide_sdio �Ƿ�ʹ��4λSDIO����
				init_res SD����ʼ�����(�ṹ��ָ��)
				baseaddr APB-SDIO�������ַ
@return �Ƿ�ɹ�
*************************/
int sd_card_init(ApbSDIO* sdio, uint8_t en_wide_sdio, SDCardInitRes* init_res, uint32_t baseaddr){
	ApbSDIOResp sdio_resp;
	
	apb_sdio_set_div_rate(sdio, INIT_DIV_RATE); // ����SDIOʱ�ӷ�Ƶ��
	apb_sdio_set_en_wide_sdio(sdio, en_wide_sdio); // ����SDIO����λ��
	apb_sdio_set_en_clk(sdio, 1); // ����SDIOʱ��
	
	delay_ms(100);
	
	// ����CMD0��λ
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD0, 0x00000000, 0));
	
	// ����CMD8����SD1.X��SD2.0
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD8, 0x000001AA, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.crc_err){
		return SD_CARD_INIT_CMD8_ERR;
	}else{
		init_res->sd2_supported = !sdio_resp.is_timeout;
	}
	
	// ����ACMD41
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
	
	// ����CMD2�Ի�ȡCID
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD2, 0x00000000, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD2_ERR;
	}
	
	// ����CMD3Ҫ��cardָ��һ��RCA
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD3, 0x00000000, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD3_ERR;
	}
	init_res->rca = ((uint16_t)(sdio_resp.resp_content[0] >> 16)) | ((uint16_t)(sdio_resp.resp_content[1] << 8));
	
	// ����CMD7ѡ�п�
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD7, (((uint32_t)init_res->rca) << 16), 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD7_ERR;
	}
	
	// ����CMD16ָ�����СΪ512Byte
	while(apb_sdio_wt_cmd(sdio, SD_CARD_CMD16, 0x00000200, 0));
	delay_ms(10);
	while(!__apb_sdio_is_ctrler_idle(sdio));
	apb_sdio_get_resp(sdio, &sdio_resp);
	if(sdio_resp.is_timeout || sdio_resp.crc_err){
		return SD_CARD_INIT_CMD16_ERR;
	}
	// ���SD���Ƿ���Transfer״̬
	if(((sdio_resp.resp_content[0] >> 9) & 0x0F) != 4){
		return SD_CARD_INIT_NOT_TRANSFER;
	}
	
	// ����ACMD6��������λ��
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
	
	// ����CMD6��ѯSD������
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
	
	// ����CMD6�л�������ģʽ
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
	
	apb_sdio_set_div_rate(sdio, RUNNING_DIV_RATE); // ��ʼ�����, ��������SDIOʱ�ӷ�Ƶ��
	
	return SD_CARD_INIT_SUCCESS;
}

/*************************
@io
@public
@brief  ���͵��������
@param  sdio APB-SDIO(�ṹ��ָ��)
        addr ���ַ
@return �Ƿ�ɹ�
*************************/
int sd_card_send_read_single_block_cmd(ApbSDIO* sdio, uint32_t addr){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD17, addr, 0);
}

/*************************
@io
@public
@brief  ���Ͷ�������
@param  sdio APB-SDIO(�ṹ��ָ��)
        addr �����ַ
        read_n ��ȡ����
@return �Ƿ�ɹ�
*************************/
int sd_card_send_read_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t read_n){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD18, addr, read_n);
}

/*************************
@io
@public
@brief  �ӻ�������ȡ����
@param  sdio APB-SDIO(�ṹ��ָ��)
        rdata �����ݻ���������ַ
@return ��ȡ����˫����
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
@brief  ���͵���д����
@param  sdio APB-SDIO(�ṹ��ָ��)
        addr ���ַ
@return �Ƿ�ɹ�
*************************/
int sd_card_send_write_single_block_cmd(ApbSDIO* sdio, uint32_t addr){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD24, addr, 0);
}

/*************************
@io
@public
@brief  ���Ͷ��д����
@param  sdio APB-SDIO(�ṹ��ָ��)
        addr ���ַ
				write_n д�����
@return �Ƿ�ɹ�
*************************/
int sd_card_send_write_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t write_n){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD25, addr, write_n);
}

/*************************
@io
@public
@brief  �򻺳���д������
@param  sdio APB-SDIO(�ṹ��ָ��)
        wdata д���ݻ���ַ
				len ��д���ݵ�˫����
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
@brief  ����ֹͣ��������
@param  sdio APB-SDIO(�ṹ��ָ��)
@attention ������Ӧ��ÿ������/д��������
@return �Ƿ�ɹ�
*************************/
int sd_card_stop_trans(ApbSDIO* sdio){
	return apb_sdio_wt_cmd(sdio, SD_CARD_CMD12, 0x00000000, 0);
}
