#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AHB_FSMC
#define __AHB_FSMC

typedef struct{
	uint32_t base_addr_regs; // ���üĴ���Ƭ����ַ
	uint32_t base_addr_mem; // FSMC����ַ
}Fsmc;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_fsmc(uint32_t base_addr, Fsmc* fsmc); // ��ʼ��FSMC������

void fsmc_cfg_rt_pars(Fsmc* fsmc, uint8_t addr_set, uint8_t data_set, uint8_t data_hold); // ����FSMC������ʱ�����

void fsmc_write_16(Fsmc* fsmc, uint32_t ofs, uint16_t data); // FSMC��������16λ����λ��д����
void fsmc_write_8(Fsmc* fsmc, uint32_t ofs, uint8_t data); // FSMC��������8λ����λ��д����

uint16_t fsmc_read_16(Fsmc* fsmc, uint32_t ofs); // FSMC��������16λ����λ�������
uint8_t fsmc_read_8(Fsmc* fsmc, uint32_t ofs); // FSMC��������8λ����λ�������
