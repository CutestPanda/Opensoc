#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AHB_FSMC
#define __AHB_FSMC

typedef struct{
	uint32_t base_addr_regs; // 配置寄存器片基地址
	uint32_t base_addr_mem; // FSMC基地址
}Fsmc;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_fsmc(uint32_t base_addr, Fsmc* fsmc); // 初始化FSMC控制器

void fsmc_cfg_rt_pars(Fsmc* fsmc, uint8_t addr_set, uint8_t data_set, uint8_t data_hold); // 配置FSMC控制器时序参数

void fsmc_write_16(Fsmc* fsmc, uint32_t ofs, uint16_t data); // FSMC控制器以16位总线位宽写数据
void fsmc_write_8(Fsmc* fsmc, uint32_t ofs, uint8_t data); // FSMC控制器以8位总线位宽写数据

uint16_t fsmc_read_16(Fsmc* fsmc, uint32_t ofs); // FSMC控制器以16位总线位宽读数据
uint8_t fsmc_read_8(Fsmc* fsmc, uint32_t ofs); // FSMC控制器以8位总线位宽读数据
