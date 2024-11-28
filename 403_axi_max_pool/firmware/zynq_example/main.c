#include "axi_max_pool.h"
#include "gic.h"

#include "xil_cache.h"
#include "xil_printf.h"

#include "time.h"
#include <stdlib.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STEP_TYPE 0 // 步长类型(0 - > 步长为1, 1 -> 步长为2)
#define FT_MAP_W 26 // 特征图宽度
#define FT_MAP_H 26 // 特征图高度
#define FT_MAP_CHN 7 // 特征图通道数

#define USE_ACP_PORT // 使用ACP接口

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void axi_max_pool_intr_handler(void* callback_ref); // AXI最大池化单元中断服务函数

void generate_ft_map(void); // 生成输入特征图
void generate_golden_ref(void); // 生成黄金参考
int check_max_pool_res(void); // 检查最大池化结果

int16_t* ptr_align(int16_t* ptr, uint32_t align_byte_n); // 生成最近的对齐地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static XScuGic gic; // 全局中断控制器(外设结构体)
static AXIMaxPool axi_max_pool; // AXI最大池化单元(外设结构体)

// 输入特征图缓存区
static int16_t in_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 512];
static int16_t* in_ft_map_buf_ptr;

// 输出特征图缓存区
static int16_t out_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 512];
static int16_t* out_ft_map_buf_ptr;

// 黄金参考
static int16_t golden_ref_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN];

// 中断标志
static uint8_t max_pool_itr_flag = 0;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(void){
	// 初始化全局中断控制器
	if(init_gic(&gic, XPAR_SCUGIC_SINGLE_DEVICE_ID) == XST_FAILURE){
		return XST_FAILURE;
	}
	// 初始化AXI最大池化单元
	init_axi_max_pool(&axi_max_pool, XPAR_AXI_MAX_POOL_0_BASEADDR);

	// 配置AXI最大池化单元的运行时参数
	AXIMaxPoolCfg axi_max_pool_cfg;

	axi_max_pool_cfg.step_type = STEP_TYPE ? STEP_2:STEP_1;
	axi_max_pool_cfg.en_top_padding = 0;
	axi_max_pool_cfg.en_bottom_padding = 1;
	axi_max_pool_cfg.en_left_padding = 0;
	axi_max_pool_cfg.en_right_padding = 1;
	axi_max_pool_cfg.feature_map_w = FT_MAP_W;
	axi_max_pool_cfg.feature_map_h = FT_MAP_H;
	axi_max_pool_cfg.feature_map_chn_n = FT_MAP_CHN;

	axi_max_pool_set_conv_params(&axi_max_pool, &axi_max_pool_cfg);

	// 生成对齐的输入/输出特征图指针
	in_ft_map_buf_ptr = ptr_align(in_ft_map_buf, FT_MAP_BUF_ALIGNMENT);
	out_ft_map_buf_ptr = ptr_align(out_ft_map_buf, FT_MAP_BUF_ALIGNMENT);

	generate_ft_map(); // 生成输入特征图
	generate_golden_ref(); // 生成黄金参考

#ifndef USE_ACP_PORT
	// 刷新数据cache
	Xil_DCacheFlushRange((INTPTR)in_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2);
	Xil_DCacheFlushRange((INTPTR)out_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2);
#endif

	// 配置AXI最大池化单元的中断
	if(gic_conn_config_itr(&gic, NULL, axi_max_pool_intr_handler, XPAR_FABRIC_AXI_MAX_POOL_0_ITR_INTR,
		20, ITR_RISING_EDGE_TG) == XST_FAILURE){
		return XST_FAILURE;
	}
	axi_max_pool_enable_itr(&axi_max_pool, AXI_MAX_POOL_ITR_DMA_S2MM_DONE);

	// 启动AXI最大池化单元的DMA读通道
	if(axi_max_pool_start_dma_rchn(&axi_max_pool, (uint32_t)in_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2)){
		return XST_FAILURE;
	}
#if STEP_TYPE == 0
	// 启动AXI最大池化单元的DMA写通道
	if(axi_max_pool_start_dma_wchn(&axi_max_pool, (uint32_t)out_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2)){
		return XST_FAILURE;
	}
#else
	// 启动AXI最大池化单元的DMA写通道
	if(axi_max_pool_start_dma_wchn(&axi_max_pool, (uint32_t)out_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) / 2)){
		return XST_FAILURE;
	}
#endif
	// 启动AXI最大池化单元的计算
	if(axi_max_pool_start_cal(&axi_max_pool)){
		return XST_FAILURE;
	}

	// 等待第1次测试返回结果
	while(!max_pool_itr_flag);

	int check_res = check_max_pool_res();

	if(check_res){
		xil_printf("max_pool res checked unsuccessfully!");
	}else{
		xil_printf("max_pool res checked successfully!");
	}

	max_pool_itr_flag = 0;

	// 清零输出特征图缓存区以准备第2次测试
	memset(out_ft_map_buf, 0, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 512) * 2);

	// 启动AXI最大池化单元的DMA读通道
	if(axi_max_pool_start_dma_rchn(&axi_max_pool, (uint32_t)in_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2)){
		return XST_FAILURE;
	}
#if STEP_TYPE == 0
	// 启动AXI最大池化单元的DMA写通道
	if(axi_max_pool_start_dma_wchn(&axi_max_pool, (uint32_t)out_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) * 2)){
		return XST_FAILURE;
	}
#else
	// 启动AXI最大池化单元的DMA写通道
	if(axi_max_pool_start_dma_wchn(&axi_max_pool, (uint32_t)out_ft_map_buf_ptr, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN) / 2)){
		return XST_FAILURE;
	}
#endif
	// 启动AXI最大池化单元的计算
	if(axi_max_pool_start_cal(&axi_max_pool)){
		return XST_FAILURE;
	}

	// 等待第2次测试返回结果
	while(!max_pool_itr_flag);

	check_res = check_max_pool_res();

	if(check_res){
		xil_printf("max_pool res checked unsuccessfully!");
	}else{
		xil_printf("max_pool res checked successfully!");
	}

	max_pool_itr_flag = 0;

	while(1);

	return XST_SUCCESS;
}

/*************************
@itr_handler
@private
@brief  AXI最大池化单元中断服务函数
@param  callback_ref 回调句柄
@return none
*************************/
void axi_max_pool_intr_handler(void* callback_ref){
	uint32_t itr_sts = axi_max_pool_get_itr_sts(&axi_max_pool); // 中断状态向量

	if(itr_sts & AXI_MAX_POOL_ITR_DMA_S2MM_DONE){
		// DMA写完成中断
		// ...
	}

	axi_max_pool_clear_itr_flag(&axi_max_pool); // 清除中断标志

	max_pool_itr_flag = 1;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@logic
@private
@brief  生成输入特征图
@param  none
@return none
*************************/
void generate_ft_map(void){
	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int j = 0;j < FT_MAP_W * FT_MAP_H;j++){
			in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + j] = rand();
		}
	}
}

/*************************
@logic
@private
@brief  生成黄金参考
@param  none
@return none
*************************/
void generate_golden_ref(void){
#if STEP_TYPE == 0
	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int y = 0;y < FT_MAP_H;y++){
			for(int x = 0;x < FT_MAP_W;x++){
				int16_t roi[2][2];
				int16_t max;

				roi[0][0] = in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x];
				roi[0][1] = (x == (FT_MAP_W - 1)) ? 0:in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x + 1];
				roi[1][0] = (y == (FT_MAP_H - 1)) ? 0:in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x];
				roi[1][1] = ((y == (FT_MAP_H - 1)) || (x == (FT_MAP_W - 1))) ?
					0:in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x + 1];

				max = roi[0][0];
				if(roi[0][1] > max)
					max = roi[0][1];
				if(roi[1][0] > max)
					max = roi[1][0];
				if(roi[1][1] > max)
					max = roi[1][1];

				golden_ref_buf[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x] = max;
			}
		}
	}
#else
	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int y = 0;y < FT_MAP_H;y++){
			for(int x = 0;x < FT_MAP_W;x++){
				if((x % 2) || (y % 2))
					continue;

				int16_t roi[2][2];
				int16_t max;

				roi[0][0] = in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x];
				roi[0][1] = in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x + 1];
				roi[1][0] = in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x];
				roi[1][1] = in_ft_map_buf_ptr[i * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x + 1];

				max = roi[0][0];
				if(roi[0][1] > max)
					max = roi[0][1];
				if(roi[1][0] > max)
					max = roi[1][0];
				if(roi[1][1] > max)
					max = roi[1][1];

				golden_ref_buf[i * (FT_MAP_W / 2) * (FT_MAP_H / 2) + (y >> 1) * (FT_MAP_W / 2) + (x >> 1)] = max;
			}
		}
	}
#endif
}

/*************************
@check
@private
@brief  检查最大池化结果
@param  none
@return 是否一致
*************************/
int check_max_pool_res(void){
	uint8_t success = 1;

#if STEP_TYPE == 0
	for(int i = 0;i < FT_MAP_W * FT_MAP_H * FT_MAP_CHN;i++){
		if(out_ft_map_buf_ptr[i] != golden_ref_buf[i]){
			success = 0;
		}
	}
#else
	for(int i = 0;i < (FT_MAP_W * FT_MAP_H / 4) * FT_MAP_CHN;i++){
		if(out_ft_map_buf_ptr[i] != golden_ref_buf[i]){
			success = 0;
		}
	}
#endif

	return success ? 0:-1;
}

/*************************
@logic
@private
@brief  生成最近的对齐地址
@param  ptr 原始指针
        align_byte_n 对齐字节量
@return 对齐的指针
*************************/
int16_t* ptr_align(int16_t* ptr, uint32_t align_byte_n){
	while(((uint32_t)ptr) % align_byte_n){
		ptr++;
	}

	return ptr;
}
