/************************************************************************************************************************
通用FSMC控制器驱动(主源文件)
@brief  通用FSMC控制器驱动
@date   2024/08/29
@author 陈家耀
@eidt   2024/08/29 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "generic_fsmc_ctrler.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化FSMC控制器
@param  base_addr FSMC外设基地址
			  fsmc FSMC外设(结构体指针)
@return none
*************************/
void init_fsmc(uint32_t base_addr, Fsmc* fsmc){
	fsmc->base_addr_regs = base_addr;
	fsmc->base_addr_mem = base_addr + 0x00001000;
}

/*************************
@cfg
@public
@brief  配置FSMC控制器时序参数
@param  fsmc FSMC外设(结构体指针)
		    addr_set  地址建立周期数 - 1
			  data_set  数据建立周期数 - 1
	      data_hold 数据保持周期数 - 1
@return none
*************************/
void fsmc_cfg_rt_pars(Fsmc* fsmc, uint8_t addr_set, uint8_t data_set, uint8_t data_hold){
	uint16_t* ptr = (uint16_t*)fsmc->base_addr_regs;
	
	ptr[0] = ((uint16_t)addr_set) | (((uint16_t)data_set) << 8);
	ptr[1] = (uint16_t)data_hold;
}

/*************************
@io
@public
@brief  FSMC控制器以16位总线位宽写数据
@param  fsmc FSMC外设(结构体指针)
		    ofs FSMC存储偏移地址
        data 待写的半字数据
@return none
*************************/
void fsmc_write_16(Fsmc* fsmc, uint32_t ofs, uint16_t data){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + ofs);
	
	*ptr = data;
}

/*************************
@io
@public
@brief  FSMC控制器以8位总线位宽写数据
@param  fsmc FSMC外设(结构体指针)
		    ofs FSMC存储偏移地址
        data 待写的字节数据
@return none
*************************/
void fsmc_write_8(Fsmc* fsmc, uint32_t ofs, uint8_t data){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + (ofs << 1));
	
	*ptr = (uint16_t)data;
}

/*************************
@io
@public
@brief  FSMC控制器以16位总线位宽读数据
@param  fsmc FSMC外设(结构体指针)
		    ofs FSMC存储偏移地址
@return 读取到的半字数据
*************************/
uint16_t fsmc_read_16(Fsmc* fsmc, uint32_t ofs){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + ofs);
	
	return *ptr;
}

/*************************
@io
@public
@brief  FSMC控制器以8位总线位宽读数据
@param  fsmc FSMC外设(结构体指针)
		    ofs FSMC存储偏移地址
@return 读取到的字节数据
*************************/
uint8_t fsmc_read_8(Fsmc* fsmc, uint32_t ofs){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + (ofs << 1));
	
	return (uint8_t)(*ptr & 0x00FF);
}
