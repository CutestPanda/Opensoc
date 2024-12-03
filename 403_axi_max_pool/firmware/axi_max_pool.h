#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж���������
#define AXI_MAX_POOL_ITR_ALL 0x00000007
#define AXI_MAX_POOL_ITR_DMA_MM2S_DONE 0x00000001 // DMA������ж�
#define AXI_MAX_POOL_ITR_DMA_S2MM_DONE 0x00000002 // DMAд����ж�
#define AXI_MAX_POOL_ITR_CAL_DONE 0x00000004 // ���ػ���������ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_MAX_POOL_H

#define __AXI_MAX_POOL_H

// ���Ͷ���:��������
typedef enum{
	STEP_1, STEP_2
}StepType;

// ���Ͷ���: ���ػ���Ԫ�ļĴ�����
typedef struct{
	uint32_t ctrl_sts;
	uint32_t in_ft_map_buf_baseaddr;
	uint32_t in_ft_map_buf_len;
	uint32_t out_ft_map_buf_baseaddr;
	uint32_t out_ft_map_buf_len;
	uint32_t itr_en;
	uint32_t itr_flag;
	uint32_t step_padding;
	uint32_t feature_map_c_w;
	uint32_t feature_map_h;
}AXIMaxPoolHw;

// ���Ͷ���: ���ػ���Ԫ������ʱ����
typedef struct{
	StepType step_type;
	uint8_t en_top_padding;
	uint8_t en_bottom_padding;
	uint8_t en_left_padding;
	uint8_t en_right_padding;
	uint16_t feature_map_w;
	uint16_t feature_map_h;
	uint16_t feature_map_chn_n;
}AXIMaxPoolCfg;

// ���Ͷ���: ���ػ���Ԫ��������
typedef struct{
	AXIMaxPoolHw* hardware;
}AXIMaxPool;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_max_pool(AXIMaxPool* axi_max_pool, uint32_t baseaddr); // ��ʼ��AXI���ػ���Ԫ

void axi_max_pool_set_conv_params(AXIMaxPool* axi_max_pool, AXIMaxPoolCfg* cfg); // ����AXI���ػ���Ԫ������ʱ����

int axi_max_pool_start_cal(AXIMaxPool* axi_max_pool); // ����AXI���ػ���Ԫ�ļ���
int axi_max_pool_start_dma_rchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // ����AXI���ػ���Ԫ��DMA��ͨ��
int axi_max_pool_start_dma_wchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // ����AXI���ػ���Ԫ��DMAдͨ��

void axi_max_pool_enable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask); // ʹ��AXI���ػ���Ԫ���ж�
void axi_max_pool_disable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask); // ����AXI���ػ���Ԫ���ж�

uint32_t axi_max_pool_get_itr_sts(AXIMaxPool* axi_max_pool); // ��ȡAXI���ػ���Ԫ���ж�״̬
void axi_max_pool_clear_itr_flag(AXIMaxPool* axi_max_pool); // ���AXI���ػ���Ԫ���жϱ�־
