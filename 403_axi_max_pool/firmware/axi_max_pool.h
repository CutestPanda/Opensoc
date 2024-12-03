#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断类型掩码
#define AXI_MAX_POOL_ITR_ALL 0x00000007
#define AXI_MAX_POOL_ITR_DMA_MM2S_DONE 0x00000001 // DMA读完成中断
#define AXI_MAX_POOL_ITR_DMA_S2MM_DONE 0x00000002 // DMA写完成中断
#define AXI_MAX_POOL_ITR_CAL_DONE 0x00000004 // 最大池化计算完成中断

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_MAX_POOL_H

#define __AXI_MAX_POOL_H

// 类型定义:步长类型
typedef enum{
	STEP_1, STEP_2
}StepType;

// 类型定义: 最大池化单元的寄存器区
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

// 类型定义: 最大池化单元的运行时参数
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

// 类型定义: 最大池化单元的外设句柄
typedef struct{
	AXIMaxPoolHw* hardware;
}AXIMaxPool;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_max_pool(AXIMaxPool* axi_max_pool, uint32_t baseaddr); // 初始化AXI最大池化单元

void axi_max_pool_set_conv_params(AXIMaxPool* axi_max_pool, AXIMaxPoolCfg* cfg); // 配置AXI最大池化单元的运行时参数

int axi_max_pool_start_cal(AXIMaxPool* axi_max_pool); // 启动AXI最大池化单元的计算
int axi_max_pool_start_dma_rchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // 启动AXI最大池化单元的DMA读通道
int axi_max_pool_start_dma_wchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len); // 启动AXI最大池化单元的DMA写通道

void axi_max_pool_enable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask); // 使能AXI最大池化单元的中断
void axi_max_pool_disable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask); // 除能AXI最大池化单元的中断

uint32_t axi_max_pool_get_itr_sts(AXIMaxPool* axi_max_pool); // 获取AXI最大池化单元的中断状态
void axi_max_pool_clear_itr_flag(AXIMaxPool* axi_max_pool); // 清除AXI最大池化单元的中断标志
