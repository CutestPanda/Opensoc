#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж�ʹ������
#define APB_SDIO_RDATA_ITR_EN 0x01 // �������ж�
#define APB_SDIO_WDATA_ITR_EN 0x02 // д�����ж�
#define APB_SDIO_COMMON_ITR_EN 0x04 // �������������ж�

// �ж�״̬����
#define APB_SDIO_RDATA_ITR_STS 0x01 // �������ж�
#define APB_SDIO_WDATA_ITR_STS 0x02 // д�����ж�
#define APB_SDIO_COMMON_ITR_STS 0x04 // �������������ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_SDIO_H
#define __APB_SDIO_H

typedef struct{
	uint32_t fifo_sts; // fifo״̬
	uint32_t cmd_id_rw_n; // �����+��д�����(д�üĴ���ʱ���������fifoдʹ��)
	uint32_t cmd_par; // �������
	uint32_t rdata; // ������(���üĴ���ʱ�����������fifo��ʹ��)
	uint32_t wdata; // д����(д�üĴ���ʱ�����д����fifoдʹ��)
	uint32_t itr_en; // �ж�ʹ��
	uint32_t itr_flag; // �жϱ�־
	uint32_t resp_field3; // ��Ӧ[119:88]
	uint32_t resp_field2; // ��Ӧ[87:56]
	uint32_t resp_field1; // ��Ӧ[55:24]
	uint32_t resp_field0_sts; // ��Ӧ[23:0] + ״̬
	uint32_t ctrler_cs; // ����������ʱ���� + ״̬
}ApbSDIOHd;

typedef struct{
	ApbSDIOHd* hardware;
	uint8_t en_sdio_clk;
	uint8_t en_wide_sdio;
	uint16_t sdio_div_rate;
}ApbSDIO;

typedef struct{
	uint32_t resp_content[4]; // [23:0], [55:24], [87:56], [119:88]
	uint8_t is_long_resp;
	uint8_t crc_err;
	uint8_t is_timeout;
}ApbSDIOResp;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define __apb_sdio_is_ctrler_idle(sdio) ((sdio)->hardware->ctrler_cs & 0x00000001)
#define __apb_sdio_get_rdata_sts(sdio) (((sdio)->hardware->ctrler_cs >> 1) & 0x0000001F)
#define __apb_sdio_get_wdata_sts(sdio) (((sdio)->hardware->ctrler_cs >> 8) & 0x00000007)

#define __apb_sdio_get_itr_status(sdio) ((uint8_t)(((sdio)->hardware->itr_flag >> 8) & 0x000000FF))
#define __apb_sdio_clear_itr_flag(sdio) ((sdio)->hardware->itr_flag = 0x00000000)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_sdio_init(ApbSDIO* sdio, uint32_t base_addr);

void apb_sdio_set_en_clk(ApbSDIO* sdio, uint8_t en_sdio_clk);
void apb_sdio_set_en_wide_sdio(ApbSDIO* sdio, uint8_t en_wide_sdio);
void apb_sdio_set_div_rate(ApbSDIO* sdio, uint16_t div_rate);
void apb_sdio_get_resp(ApbSDIO* sdio, ApbSDIOResp* resp);

void apb_sdio_enable_itr(ApbSDIO* sdio, uint8_t itr_en);
void apb_sdio_disable_itr(ApbSDIO* sdio);

int apb_sdio_wt_cmd(ApbSDIO* sdio, uint8_t cmd_id, uint32_t cmd_par, uint8_t rw_n);
int apb_sdio_read_data(ApbSDIO* sdio, uint32_t* rdata);
int apb_sdio_wt_data(ApbSDIO* sdio, uint32_t wdata);
