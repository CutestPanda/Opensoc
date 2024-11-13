#include "axi_generic_conv.h"
#include "gic.h"

#include "xil_cache.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define PRL_KERNAL_N 4 // 核并行数
#define PRL_CHN_N 4 // 通道并行数

#define FT_MAP_W 8 // 特征图宽度
#define FT_MAP_H 3 // 特征图高度
#define FT_MAP_CHN 5 // 特征图通道数
#define KERNAL_N 5 // 卷积核个数

#define RD_REQ_DSC_BUF_LEN 1024 * 2 + 64 // 读请求描述子缓存区长度(以双字计)
#define WT_REQ_DSC_BUF_LEN 1024 * 2 + 64 // 写请求描述子缓存区长度(以双字计)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void axi_generic_conv_intr_handler(void* callback_ref); // AXI通用卷积加速器中断服务函数

void generate_ft_pars(void); // 生成输入特征图/卷积核参数/线性参数
uint32_t* ptr_align(uint32_t* ptr, uint32_t align_byte_n); // 生成最近的对齐地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static XScuGic gic; // 全局中断控制器(外设结构体)
static AXIGenericConv axi_conv; // AXI通用卷积加速器(外设结构体)

// 输入特征图缓存区
static uint16_t in_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4];
// 卷积核缓存区
static uint16_t kernal_buf[3 * 3 * FT_MAP_CHN * KERNAL_N + 4];
// 线性参数A缓存区
static uint16_t linear_a_buf[FT_MAP_CHN + 4];
// 线性参数B缓存区
static uint16_t linear_b_buf[FT_MAP_CHN + 4];
// 输出特征图缓存区
static uint16_t out_ft_map_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];

// 读请求描述子缓存区
static uint32_t rd_req_dsc_buf[RD_REQ_DSC_BUF_LEN];
static uint32_t* rd_req_dsc_buf_ptr;
static uint32_t rd_req_n;
// 写请求描述子缓存区
static uint32_t wt_req_dsc_buf[WT_REQ_DSC_BUF_LEN];
static uint32_t* wt_req_dsc_buf_ptr;
static uint32_t wt_req_n;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(void){
	// 初始化全局中断控制器
	if(init_gic(&gic, XPAR_SCUGIC_SINGLE_DEVICE_ID) == XST_FAILURE){
		return XST_FAILURE;
	}
	// 初始化AXI通用卷积加速器
	init_axi_generic_conv(&axi_conv, XPAR_AXI_GENERIC_CONV_0_BASEADDR);

	// 配置AXI通用卷积加速器的运行时参数
	AXIGenericConvCfg axi_conv_cfg;

	axi_conv_cfg.kernal_type = TYPE_3x3;
	axi_conv_cfg.en_top_padding = 1;
	axi_conv_cfg.en_bottom_padding = 1;
	axi_conv_cfg.en_left_padding = 1;
	axi_conv_cfg.en_right_padding = 1;
	axi_conv_cfg.feature_map_w = FT_MAP_W;
	axi_conv_cfg.feature_map_h = FT_MAP_H;
	axi_conv_cfg.feature_map_chn_n = FT_MAP_CHN;
	axi_conv_cfg.kernal_n = KERNAL_N;
	axi_conv_cfg.act_rate_c_0 = (1 << 14);
	axi_conv_cfg.act_rate_c_1 = 0;

	axi_generic_conv_set_conv_params(&axi_conv, &axi_conv_cfg);

	// 生成输入特征图/卷积核参数/线性参数
	generate_ft_pars();
	// 生成对齐的读请求描述子缓存区指针
	rd_req_dsc_buf_ptr = ptr_align(rd_req_dsc_buf, RD_REQ_BUF_ALIGNMENT);
	// 生成对齐的写请求描述子缓存区指针
	wt_req_dsc_buf_ptr = ptr_align(wt_req_dsc_buf, WT_REQ_BUF_ALIGNMENT);
	// 生成读请求描述子
	rd_req_n = axi_generic_conv_generate_rd_req_dsc(rd_req_dsc_buf_ptr, (uint32_t)linear_a_buf, (uint32_t)linear_b_buf,
		(uint32_t)kernal_buf, (uint32_t)in_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_CHN, PRL_CHN_N,
		FT_MAP_W, FT_MAP_H, 1, 1);
	// 生成写请求描述子
	wt_req_n = axi_generic_conv_generate_wt_req_dsc(wt_req_dsc_buf_ptr, (uint32_t)out_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_W, FT_MAP_H);

	// 刷新数据Cache
	Xil_DCacheFlushRange((INTPTR)in_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)kernal_buf, (3 * 3 * FT_MAP_CHN * KERNAL_N + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_a_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_b_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)rd_req_dsc_buf, RD_REQ_DSC_BUF_LEN * 4);
	Xil_DCacheFlushRange((INTPTR)wt_req_dsc_buf, WT_REQ_DSC_BUF_LEN * 4);

	// 启动AXI通用卷积加速器
	axi_generic_conv_start(&axi_conv);

	// 配置AXI通用卷积加速器的中断
	if(gic_conn_config_itr(&gic, NULL, axi_generic_conv_intr_handler, XPAR_FABRIC_AXI_GENERIC_CONV_0_ITR_INTR,
		20, ITR_RISING_EDGE_TG) == XST_FAILURE){
		return XST_FAILURE;
	}
	axi_generic_conv_set_wt_req_itr_th(&axi_conv, FT_MAP_H * KERNAL_N);
	axi_generic_conv_enable_itr(&axi_conv, AXI_GENERIC_CONV_ITR_WT_FNS);

	// 提交读请求描述子
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf_ptr, rd_req_n)){
		return XST_FAILURE;
	}
	// 提交写请求描述子
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf_ptr, wt_req_n)){
		return XST_FAILURE;
	}

	while(1){

	}

	return XST_SUCCESS;
}

/*************************
@itr_handler
@private
@brief  AXI通用卷积加速器中断服务函数
@param  callback_ref 回调句柄
@return none
*************************/
void axi_generic_conv_intr_handler(void* callback_ref){
	uint32_t itr_sts = axi_generic_conv_get_itr_sts(&axi_conv); // 中断状态向量

	if(itr_sts & AXI_GENERIC_CONV_ITR_WT_FNS){
		// 写请求处理完成中断
		Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);
	}

	axi_generic_conv_clear_itr_flag(&axi_conv); // 清除中断标志
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@logic
@private
@brief  生成输入特征图/卷积核参数/线性参数
@param  none
@return none
*************************/
void generate_ft_pars(void){
	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int j = 0;j < FT_MAP_W * FT_MAP_H;j++){
			in_ft_map_buf[i * FT_MAP_W * FT_MAP_H + j] = j + 1;
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		for(int j = 0;j < FT_MAP_CHN;j++){
			for(int m = 0;m < 9;m++){
				kernal_buf[i * FT_MAP_CHN * 9 + j * 9 + m] = (1 << 10);
			}
		}
	}

	for(int i = 0;i < FT_MAP_CHN;i++){
		linear_a_buf[i] = (1 << 12);
		linear_b_buf[i] = 0;
	}
}

/*************************
@logic
@private
@brief  生成最近的对齐地址
@param  ptr 原始指针
        align_byte_n 对齐字节量
@return 对齐的指针
*************************/
uint32_t* ptr_align(uint32_t* ptr, uint32_t align_byte_n){
	while(((uint32_t)ptr) % align_byte_n){
		ptr++;
	}

	return ptr;
}
