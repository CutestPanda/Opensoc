/************************************************************************************************************************
SD������������(�ӿ�ͷ�ļ�)
@brief  SD������������
@date   2024/09/07
@author �¼�ҫ
************************************************************************************************************************/

#include "apb_sdio.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ��ʼ�����
#define SD_CARD_INIT_CMD8_ERR -1 // CMD8����
#define SD_CARD_INIT_ACMD41_ERR -2 // ACMD41����
#define SD_CARD_INIT_POWER_UP_FAILED -3 // �ϵ�ʧ��
#define SD_CARD_INIT_CMD2_ERR -4 // CMD2����
#define SD_CARD_INIT_CMD3_ERR -5 // CMD3����
#define SD_CARD_INIT_CMD7_ERR -6 // CMD7����
#define SD_CARD_INIT_CMD16_ERR -7 // CMD16����
#define SD_CARD_INIT_NOT_TRANSFER -8 // δ����Transfer״̬
#define SD_CARD_INIT_ACMD6_ERR -9 // ACMD6����
#define SD_CARD_INIT_CMD6_ERR -10 // CMD6����
#define SD_CARD_INIT_SUCCESS 0 // �ɹ�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __SD_CARD_H
#define __SD_CARD_H

typedef struct{
	uint8_t sd2_supported; // �Ƿ�֧��SD2.0
	uint8_t large_volume; // �Ƿ��������
	uint16_t rca; // ���Ƽ���ַ(RCA)
}SDCardInitRes;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ��ʼ��SD��
int sd_card_init(ApbSDIO* sdio, uint8_t en_wide_sdio, SDCardInitRes* init_res, uint32_t baseaddr);

// ���͵��������
int sd_card_send_read_single_block_cmd(ApbSDIO* sdio, uint32_t addr);
// ���Ͷ�������
int sd_card_send_read_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t read_n);
// �ӻ�������ȡ����
uint32_t sd_card_read_data_block(ApbSDIO* sdio, uint32_t* rdata);

// ���͵���д����
int sd_card_send_write_single_block_cmd(ApbSDIO* sdio, uint32_t addr);
// ���Ͷ��д����
int sd_card_send_write_mul_block_cmd(ApbSDIO* sdio, uint32_t addr, uint8_t write_n);
// �򻺳���д������
void sd_card_write_data_block(ApbSDIO* sdio, uint32_t* wdata, uint32_t len);

// ����ֹͣ��������
int sd_card_stop_trans(ApbSDIO* sdio);
