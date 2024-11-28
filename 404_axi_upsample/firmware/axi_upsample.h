#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断类型掩码
#define AXI_UPSAMPLE_ITR_ALL 0x00000003
#define AXI_UPSAMPLE_ITR_DMA_MM2S_DONE 0x00000001 // DMA读完成中断
#define AXI_UPSAMPLE_ITR_DMA_S2MM_DONE 0x00000002 // DMA写完成中断

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define FT_MAP_BUF_ALIGNMENT 256 // 输入/输出特征图缓存区首地址对齐到的字节数

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_UPSAMPLE_H

#define __AXI_UPSAMPLE_H

// 类型定义: 上采样单元的寄存器区
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

// 类型定义: 上采样单元的运行时参数
typedef struct{
	uint16_t feature_map_w;
	uint16_t feature_map_h;
	uint16_t feature_map_chn_n;
}AXIUpsampleCfg;

// 类型定义: 上采样单元的外设句柄
typedef struct{
	AXIUpsampleHw* hardware;
}AXIUpsample;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_upsample(AXIUpsample* axi_upsample, uint32_t baseaddr); // 初始化AXI上采样单元

void axi_upsample_set_conv_params(AXIUpsample* axi_upsample, AXIUpsampleCfg* cfg); // 配置AXI上采样单元的运行时参数

int axi_upsample_start_dma_rchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // 启动AXI上采样单元的DMA读通道
int axi_upsample_start_dma_wchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // 启动AXI上采样单元的DMA写通道

void axi_upsample_enable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask); // 使能AXI上采样单元的中断
void axi_upsample_disable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask); // 除能AXI上采样单元的中断

uint32_t axi_upsample_get_itr_sts(AXIUpsample* axi_upsample); // 获取AXI上采样单元的中断状态
void axi_upsample_clear_itr_flag(AXIUpsample* axi_upsample); // 清除AXI上采样单元的中断标志
