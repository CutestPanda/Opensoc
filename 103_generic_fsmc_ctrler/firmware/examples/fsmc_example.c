/************************************************************************************************************************
FSMC控制器示例代码
@brief  基于FSMC控制器实现外部SRAM读写
@date   2024/08/29
@author 陈家耀
@eidt   2024/08/29 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../generic_fsmc_ctrler.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_FSMC 0x60000000 // FSMC外设基地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static Fsmc fsmc; // FSMC控制器外设结构体

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void fsmc_example(void){
	init_fsmc(BASEADDR_FSMC, &fsmc); // 初始化FSMC外设
	
	/*
	配置FSMC控制器时序参数
	
	地址建立周期数 = 10
	数据建立周期数 = 10
	数据保持周期数 = 10
	*/
	fsmc_cfg_rt_pars(&fsmc, 9, 9, 9);
	
	/** 写外部SRAM **/
	for(uint32_t i = 0;i < 50;i++){
		fsmc_write_16(&fsmc, i << 1, i + 1);
	}
	
	/** 读外部SRAM **/
	uint8_t verify_ok = 1;
	
	for(uint32_t i = 0;i < 50;i++){
		uint16_t d = fsmc_read_16(&fsmc, i << 1);
		
		if(d != (i + 1)){
			verify_ok = 0;
			
			break;
		}
	}
	
	/** 验证读写数据一致性 **/
	if(verify_ok){
		// 读写数据一致
		// ...
	}else{
		// 读写数据不一致
		// ...
	}
	
	while(1);
}
