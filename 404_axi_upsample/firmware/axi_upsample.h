#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж���������
#define AXI_UPSAMPLE_ITR_ALL 0x00000003
#define AXI_UPSAMPLE_ITR_DMA_MM2S_DONE 0x00000001 // DMA������ж�
#define AXI_UPSAMPLE_ITR_DMA_S2MM_DONE 0x00000002 // DMAд����ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define FT_MAP_BUF_ALIGNMENT 256 // ����/�������ͼ�������׵�ַ���뵽���ֽ���

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_UPSAMPLE_H

#define __AXI_UPSAMPLE_H

// ���Ͷ���: �ϲ�����Ԫ�ļĴ�����
typedef struct{
	uint32_t ctrl_sts;
	uint32_t in_ft_map_buf_baseaddr;
	uint32_t in_ft_map_buf_len;
	uint32_t out_ft_map_buf_baseaddr;
	uint32_t out_ft_map_buf_len;
	uint32_t itr_en;
	uint32_t itr_flag;
	uint32_t feature_map_c_w;
	uint32_t feature_map_h;
}AXIUpsampleHw;

// ���Ͷ���: �ϲ�����Ԫ������ʱ����
typedef struct{
	uint16_t feature_map_w;
	uint16_t feature_map_h;
	uint16_t feature_map_chn_n;
}AXIUpsampleCfg;

// ���Ͷ���: �ϲ�����Ԫ��������
typedef struct{
	AXIUpsampleHw* hardware;
}AXIUpsample;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_upsample(AXIUpsample* axi_upsample, uint32_t baseaddr); // ��ʼ��AXI�ϲ�����Ԫ

void axi_upsample_set_conv_params(AXIUpsample* axi_upsample, AXIUpsampleCfg* cfg); // ����AXI�ϲ�����Ԫ������ʱ����

int axi_upsample_start_dma_rchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // ����AXI�ϲ�����Ԫ��DMA��ͨ��
int axi_upsample_start_dma_wchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // ����AXI�ϲ�����Ԫ��DMAдͨ��

void axi_upsample_enable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask); // ʹ��AXI�ϲ�����Ԫ���ж�
void axi_upsample_disable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask); // ����AXI�ϲ�����Ԫ���ж�

uint32_t axi_upsample_get_itr_sts(AXIUpsample* axi_upsample); // ��ȡAXI�ϲ�����Ԫ���ж�״̬
void axi_upsample_clear_itr_flag(AXIUpsample* axi_upsample); // ���AXI�ϲ�����Ԫ���жϱ�־
