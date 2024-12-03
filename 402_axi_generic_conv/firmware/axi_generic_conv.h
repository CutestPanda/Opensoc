#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断类型掩码
#define AXI_GENERIC_CONV_ITR_ALL 0x00000007
#define AXI_GENERIC_CONV_ITR_RD_REQ_DSC_DMA 0x00000001 // 读请求描述子DMA请求处理完成中断
#define AXI_GENERIC_CONV_ITR_WT_REQ_DSC_DMA 0x00000002 // 写请求描述子DMA请求处理完成中断
#define AXI_GENERIC_CONV_ITR_WT_FNS 0x00000004 // 写请求处理完成中断

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_GENERIC_CONV_H

#define __AXI_GENERIC_CONV_H

// 类型定义:卷积核类型
typedef enum{
	TYPE_3x3, TYPE_1x1
}KernalType;

// 类型定义: 通用卷积计算单元的寄存器区
typedef struct{
	uint32_t ctrl_sts;
	uint32_t itr_en;
	uint32_t itr_flag;
	uint32_t wt_req_itr_th;
	uint32_t flow_en;
	uint32_t kernal_style;
	uint32_t rd_req_buf_baseaddr;
	uint32_t rd_req_n;
	uint32_t wt_req_buf_baseaddr;
	uint32_t wt_req_n;
	uint32_t feature_map_w_h;
	uint32_t kernal_c_n;
	uint32_t act_rate_c_0;
	uint32_t act_rate_c_1;
	uint32_t wt_req_fns_n;
}AXIGenericConvHw;

// 类型定义: 通用卷积计算单元的运行时参数
typedef struct{
	KernalType kernal_type;
	uint8_t en_top_padding;
	uint8_t en_bottom_padding;
	uint8_t en_left_padding;
	uint8_t en_right_padding;
	uint16_t feature_map_w;
	uint16_t feature_map_h;
	uint16_t feature_map_chn_n;
	uint16_t kernal_n;
	int32_t act_rate_c_0;
	int32_t act_rate_c_1;
}AXIGenericConvCfg;

// 类型定义: 通用卷积计算单元的外设句柄
typedef struct{
	AXIGenericConvHw* hardware;
}AXIGenericConv;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_generic_conv(AXIGenericConv* axi_conv, uint32_t baseaddr); // 初始化AXI通用卷积加速器

void axi_generic_conv_set_conv_params(AXIGenericConv* axi_conv, AXIGenericConvCfg* cfg); // 配置AXI通用卷积加速器的运行时参数
void axi_generic_conv_start(AXIGenericConv* axi_conv); // 启动AXI通用卷积加速器
void axi_generic_conv_resume(AXIGenericConv* axi_conv); // 继续运行AXI通用卷积加速器
void axi_generic_conv_suspend(AXIGenericConv* axi_conv); // 暂停AXI通用卷积加速器
void axi_generic_conv_enable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask); // 使能AXI通用卷积加速器的中断
void axi_generic_conv_disable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask); // 除能AXI通用卷积加速器的中断
void axi_generic_conv_set_wt_req_itr_th(AXIGenericConv* axi_conv, uint32_t wt_req_itr_th); // 设置AXI通用卷积加速器的写请求处理完成中断阈值
uint32_t axi_generic_conv_get_itr_sts(AXIGenericConv* axi_conv); // 获取AXI通用卷积加速器的中断状态
void axi_generic_conv_clear_itr_flag(AXIGenericConv* axi_conv); // 清除AXI通用卷积加速器的中断标志
int axi_generic_conv_post_rd_req_dsc(AXIGenericConv* axi_conv, uint32_t rd_req_buf_baseaddr, uint32_t rd_req_n); // 向AXI通用卷积加速器提交读请求描述子
int axi_generic_conv_post_wt_req_dsc(AXIGenericConv* axi_conv, uint32_t wt_req_buf_baseaddr, uint32_t wt_req_n); // 向AXI通用卷积加速器提交写请求描述子
void axi_generic_conv_set_wt_req_fns_n(AXIGenericConv* axi_conv, uint32_t wt_req_fns_n); //设置AXI通用卷积加速器已完成的写请求个数
uint8_t axi_generic_conv_is_rd_req_dsc_dma_busy(AXIGenericConv* axi_conv); // 判断AXI通用卷积加速器的读请求描述子DMA是否忙碌
uint8_t axi_generic_conv_is_wt_req_dsc_dma_busy(AXIGenericConv* axi_conv); // 判断AXI通用卷积加速器的写请求描述子DMA是否忙碌
uint32_t axi_generic_conv_get_wt_req_fns_n(AXIGenericConv* axi_conv); //获取AXI通用卷积加速器已完成的写请求个数

// 生成读请求描述子
uint32_t axi_generic_conv_generate_rd_req_dsc(uint32_t* rd_req_dsc_buf_ptr,
	uint32_t linear_a_buf_baseaddr, uint32_t linear_b_buf_baseaddr, uint32_t kernal_buf_baseaddr, uint32_t in_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t ft_map_chn_n, uint8_t prl_chn_n,
	uint32_t in_ft_map_w, uint32_t in_ft_map_h,
	uint8_t en_top_padding, uint8_t en_bottom_padding,
	KernalType kernal_type);
// 生成写请求描述子
uint32_t axi_generic_conv_generate_wt_req_dsc(
	uint32_t* wt_req_dsc_buf_ptr,
	uint32_t out_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t out_ft_map_w, uint32_t out_ft_map_h);
