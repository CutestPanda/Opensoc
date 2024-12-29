#include "axi_generic_conv.h"
#include "gic.h"

#include "xil_cache.h"
#include "xil_printf.h"

#include "time.h"
#include <stdlib.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define KERNAL_TYPE 1 // 卷积核类型(1 -> 3x3, 0 -> 1x1)
#define STEP_TYPE 1 // 步长类型(0 -> 从第1个ROI开始, 1 -> 舍弃第1个ROI)

#define PRL_KERNAL_N 4 // 核并行数
#define PRL_CHN_N 1 // 通道并行数

#define FT_MAP_W 14 // 特征图宽度
#define FT_MAP_H 14 // 特征图高度
#define FT_MAP_CHN 128 // 特征图通道数
#define KERNAL_N 256 // 卷积核个数

#define H_STEP 2 // 水平步长
#define V_STEP 2 // 垂直步长
#define O_FT_MAP_W 7 // 输出特征图宽度
#define O_FT_MAP_H 7 // 输出特征图高度

#define ACT_RATE_C (1 << 13) // Relu激活系数

#define IN_FT_QUAZ_ACC 8 // 特征点量化精度
#define CONV_RES_EXT_FRAC_WIDTH 4 // 卷积结果额外考虑的小数位数
#define CONV_RES_EXT_INT_WIDTH 4 // 卷积结果额外考虑的整数位数
#define AB_QUAZ_ACC 8 // a/b系数量化精度
#define C_QUAZ_ACC 14 // c系数量化精度

#define RD_REQ_BUF_ALIGNMENT 64 // 读请求描述子缓存区首地址对齐到的字节数
#define WT_REQ_BUF_ALIGNMENT 64 // 写请求描述子缓存区首地址对齐到的字节数
#define MAX_RD_REQ_N 1024 * 1024 * 16 // 最大的读请求个数
#define MAX_WT_REQ_N 65536 // 最大的写请求个数

#define USE_ACP_PORT // 使用ACP接口

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void axi_generic_conv_intr_handler(void* callback_ref); // AXI通用卷积加速器中断服务函数

void generate_ft_pars(void); // 生成输入特征图/卷积核参数/线性参数
void generate_golden_ref(void); // 生成黄金参考
int check_conv_res(void); // 检查卷积结果

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static XScuGic gic; // 全局中断控制器(外设结构体)
static AXIGenericConv axi_conv; // AXI通用卷积加速器(外设结构体)

// 输入特征图缓存区
static uint16_t in_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4];
// 卷积核缓存区
static uint16_t kernal_buf[(KERNAL_TYPE ? 9:1) * FT_MAP_CHN * KERNAL_N + 4];
// 线性参数A缓存区
static uint16_t linear_a_buf[KERNAL_N + 4];
// 线性参数B缓存区
static uint16_t linear_b_buf[KERNAL_N + 4];
// 输出特征图缓存区
static uint16_t out_ft_map_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];
// 黄金参考
static uint16_t golden_ref_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];

// 读请求描述子缓存区
static uint32_t rd_req_dsc_buf[MAX_RD_REQ_N * 2 + 64] __attribute__ ((aligned(RD_REQ_BUF_ALIGNMENT)));
static uint32_t rd_req_n;
// 写请求描述子缓存区
static uint32_t wt_req_dsc_buf[MAX_WT_REQ_N * 2 + 64] __attribute__ ((aligned(WT_REQ_BUF_ALIGNMENT)));
static uint32_t wt_req_n;

// 中断标志
static uint8_t conv_itr_flag = 0;

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

	axi_conv_cfg.kernal_type = KERNAL_TYPE ? TYPE_3x3:TYPE_1x1;
	axi_conv_cfg.en_top_padding = 1;
	axi_conv_cfg.en_bottom_padding = 1;
	axi_conv_cfg.en_left_padding = 1;
	axi_conv_cfg.en_right_padding = 1;
	axi_conv_cfg.feature_map_w = FT_MAP_W;
	axi_conv_cfg.feature_map_h = FT_MAP_H;
	axi_conv_cfg.feature_map_chn_n = FT_MAP_CHN;
	axi_conv_cfg.kernal_n = KERNAL_N;
	axi_conv_cfg.act_rate_c_0 = ACT_RATE_C;
	axi_conv_cfg.act_rate_c_1 = 0;
	axi_conv_cfg.o_ft_map_w = O_FT_MAP_W;
	axi_conv_cfg.o_ft_map_h = O_FT_MAP_H;
	axi_conv_cfg.horizontal_step = H_STEP;
	axi_conv_cfg.vertical_step = V_STEP;
	axi_conv_cfg.step_type = STEP_TYPE ? NON_FIRST:FIRST;
	axi_conv_cfg.act_type = RELU;

	if(axi_generic_conv_set_conv_params(&axi_conv, &axi_conv_cfg)){
		return XST_FAILURE;
	}

	// 生成输入特征图/卷积核参数/线性参数
	generate_ft_pars();
	// 生成黄金参考
	generate_golden_ref();
	// 生成读请求描述子
	rd_req_n = axi_generic_conv_generate_rd_req_dsc(rd_req_dsc_buf, (uint32_t)linear_a_buf, (uint32_t)linear_b_buf,
		(uint32_t)kernal_buf, (uint32_t)in_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_CHN, PRL_CHN_N,
		FT_MAP_W, FT_MAP_H, 1, 1, KERNAL_TYPE ? TYPE_3x3:TYPE_1x1, V_STEP, STEP_TYPE ? NON_FIRST:FIRST);
	// 生成写请求描述子
	wt_req_n = axi_generic_conv_generate_wt_req_dsc(wt_req_dsc_buf, (uint32_t)out_ft_map_buf,
		KERNAL_N, PRL_KERNAL_N, O_FT_MAP_W, O_FT_MAP_H);

#ifndef USE_ACP_PORT
	// 刷新数据Cache
	Xil_DCacheFlushRange((INTPTR)in_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)kernal_buf, (3 * 3 * FT_MAP_CHN * KERNAL_N + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_a_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_b_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)rd_req_dsc_buf, (MAX_RD_REQ_N * 2 + 64) * 4);
	Xil_DCacheFlushRange((INTPTR)wt_req_dsc_buf, (MAX_WT_REQ_N * 2 + 64) * 4);
#endif

	// 配置AXI通用卷积加速器的中断
	if(gic_conn_config_itr(&gic, NULL, axi_generic_conv_intr_handler, XPAR_FABRIC_AXI_GENERIC_CONV_0_ITR_INTR,
		20, ITR_RISING_EDGE_TG) == XST_FAILURE){
		return XST_FAILURE;
	}
	axi_generic_conv_set_wt_req_itr_th(&axi_conv, O_FT_MAP_H * KERNAL_N);
	axi_generic_conv_enable_itr(&axi_conv, AXI_GENERIC_CONV_ITR_WT_FNS);

	// 启动AXI通用卷积加速器
	axi_generic_conv_start(&axi_conv);

	// 提交读请求描述子
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf, rd_req_n)){
		return XST_FAILURE;
	}
	// 提交写请求描述子
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf, wt_req_n)){
		return XST_FAILURE;
	}

	// 等待第1次测试返回结果
	while(!conv_itr_flag);

	int check_res = check_conv_res();

	if(check_res){
		xil_printf("conv res checked unsuccessfully!");
	}else{
		xil_printf("conv res checked successfully!");
	}

	conv_itr_flag = 0;

	// 清零输出特征图缓存区以准备第2次测试
	memset(out_ft_map_buf, 0, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);

	// 启动AXI通用卷积加速器
	axi_generic_conv_start(&axi_conv);

	// 提交读请求描述子
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf, rd_req_n)){
		return XST_FAILURE;
	}
	// 提交写请求描述子
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf, wt_req_n)){
		return XST_FAILURE;
	}

	// 等待第2次测试返回结果
	while(!conv_itr_flag);

	check_res = check_conv_res();

	if(check_res){
		xil_printf("conv res checked unsuccessfully!");
	}else{
		xil_printf("conv res checked successfully!");
	}

	conv_itr_flag = 0;

	while(1);

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
	uint32_t wt_req_fns_n = axi_generic_conv_get_wt_req_fns_n(&axi_conv); // 已完成的写请求个数

	xil_printf("wt_req_fns_n = %d", wt_req_fns_n);

	if(itr_sts & AXI_GENERIC_CONV_ITR_WT_FNS){
		// 写请求处理完成中断
#ifndef USE_ACP_PORT
		Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);
#endif
	}

	axi_generic_conv_clear_itr_flag(&axi_conv); // 清除中断标志
	axi_generic_conv_set_wt_req_fns_n(&axi_conv, 0); // 清零已完成的写请求个数

	conv_itr_flag = 1;
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
	uint16_t kernal_size = KERNAL_TYPE ? 9:1;

	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int j = 0;j < FT_MAP_W * FT_MAP_H;j++){
			in_ft_map_buf[i * FT_MAP_W * FT_MAP_H + j] = rand();
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		for(int j = 0;j < FT_MAP_CHN;j++){
			for(int m = 0;m < kernal_size;m++){
				kernal_buf[i * FT_MAP_CHN * kernal_size + j * kernal_size + m] = rand();
			}
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		linear_a_buf[i] = rand();
		linear_b_buf[i] = rand();
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
	int out_i = 0;
	uint8_t horizontal_step_cnt;
	uint8_t vertical_step_cnt;
	uint8_t horizontal_step_cmp = STEP_TYPE ? (H_STEP - 1):0;
	uint8_t vertical_step_cmp = STEP_TYPE ? (V_STEP - 1):0;

	for(int i = 0;i < KERNAL_N;i++){
		int16_t linear_a = linear_a_buf[i];
		int16_t linear_b = linear_b_buf[i];

		vertical_step_cnt = 0;

		for(int y = 0;y < FT_MAP_H;y++){
			if(vertical_step_cnt != vertical_step_cmp){
				if(vertical_step_cnt == (V_STEP - 1)){
					vertical_step_cnt = 0;
				}else{
					vertical_step_cnt++;
				}

				continue;
			}

			if(vertical_step_cnt == (V_STEP - 1)){
				vertical_step_cnt = 0;
			}else{
				vertical_step_cnt++;
			}

			horizontal_step_cnt = 0;

			for(int x = 0;x < FT_MAP_W;x++){
				int64_t conv_res = 0;

				if(horizontal_step_cnt != horizontal_step_cmp){
					if(horizontal_step_cnt == (H_STEP - 1)){
						horizontal_step_cnt = 0;
					}else{
						horizontal_step_cnt++;
					}

					continue;
				}

				if(horizontal_step_cnt == (H_STEP - 1)){
					horizontal_step_cnt = 0;
				}else{
					horizontal_step_cnt++;
				}

				for(int c = 0;c < FT_MAP_CHN;c++){
					int16_t in_ft_roi[3][3];
					int16_t kernal[3][3];

					in_ft_roi[0][0] = ((x >= 1) && (y >= 1)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[0][1] = (y >= 1) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + x]:0;
					in_ft_roi[0][2] = ((x <= (FT_MAP_W - 2)) && (y >= 1)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + (x + 1)]:0;

					in_ft_roi[1][0] = (x >= 1) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[1][1] = in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x];
					in_ft_roi[1][2] = (x <= (FT_MAP_W - 2)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + (x + 1)]:0;

					in_ft_roi[2][0] = ((x >= 1) && (y <= (FT_MAP_H - 2))) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[2][1] = (y <= (FT_MAP_H - 2)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x]:0;
					in_ft_roi[2][2] = ((x <= (FT_MAP_W - 2)) && (y <= (FT_MAP_H - 2))) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + (x + 1)]:0;

					kernal[0][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 0]:0;
					kernal[0][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 1]:0;
					kernal[0][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 2]:0;
					kernal[1][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 3]:0;
					kernal[1][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 4]:kernal_buf[FT_MAP_CHN * i + c];
					kernal[1][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 5]:0;
					kernal[2][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 6]:0;
					kernal[2][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 7]:0;
					kernal[2][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 8]:0;

					for(int m = 0;m < 3;m++){
						int32_t conv_row_res = 0;

						conv_row_res += ((int32_t)in_ft_roi[m][0]) * ((int32_t)kernal[m][0]);
						conv_row_res += ((int32_t)in_ft_roi[m][1]) * ((int32_t)kernal[m][1]);
						conv_row_res += ((int32_t)in_ft_roi[m][2]) * ((int32_t)kernal[m][2]);

						conv_row_res >>= (IN_FT_QUAZ_ACC - CONV_RES_EXT_FRAC_WIDTH);
						conv_row_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);

						conv_res += conv_row_res;
						conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);
					}
				}

				// 符号位拓展
				if(conv_res & (1 << (15 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH))){
					conv_res |= (0xFFFFFFFFFFFFFFFF << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH));
				}

				// 线性乘加
				int64_t linear_a_ext = linear_a;
				int64_t linear_b_ext = linear_b;

				conv_res = linear_a_ext * conv_res + (linear_b_ext << (IN_FT_QUAZ_ACC + CONV_RES_EXT_FRAC_WIDTH));
				conv_res >>= AB_QUAZ_ACC;
				conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);

				// 符号位拓展
				if(conv_res & (1 << (15 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH))){
					conv_res |= (0xFFFFFFFFFFFFFFFF << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH));
				}

				// Relu激活
				if(conv_res < 0){
					conv_res *= ACT_RATE_C;
					conv_res >>= C_QUAZ_ACC;
					conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);
				}

				// 舍入和溢出判断
				uint8_t is_neg = (conv_res & (1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH - 1))) ? 1:0;

#if CONV_RES_EXT_INT_WIDTH > 2
				int64_t ext_int = (conv_res >> (16 + CONV_RES_EXT_FRAC_WIDTH)) & (~(1 << (CONV_RES_EXT_INT_WIDTH - 1)));

				if((!is_neg) && (ext_int != 0)){
					// 上溢
					conv_res = 0x7FFF;
				}else if(is_neg && (ext_int != ((1 << (CONV_RES_EXT_INT_WIDTH - 1)) - 1))){
					// 下溢
					conv_res = 0x8000;
				}else{
					conv_res >>= CONV_RES_EXT_FRAC_WIDTH;
					conv_res &= ((1 << 16) - 1);

					if(is_neg){
						conv_res |= 0x8000;
					}else{
						conv_res &= 0x7FFF;
					}
				}

				golden_ref_buf[out_i] = conv_res;
#else
				conv_res >>= CONV_RES_EXT_FRAC_WIDTH;
				conv_res &= ((1 << 16) - 1);

				if(is_neg){
					conv_res |= 0x8000;
				}else{
					conv_res &= 0x7FFF;
				}

				golden_ref_buf[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x] = conv_res;
#endif
				out_i++;
			}
		}
	}
}

/*************************
@check
@private
@brief  检查卷积结果
@param  none
@return 是否一致
*************************/
int check_conv_res(void){
	uint8_t success = 1;

	for(int i = 0;i < FT_MAP_W * FT_MAP_H * KERNAL_N;i++){
		uint16_t res = out_ft_map_buf[i];
		uint16_t ref = golden_ref_buf[i];

		if(res != ref){
			success = 0;
		}
	}

	return success ? 0:-1;
}
