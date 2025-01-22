/************************************************************************************************************************
PLIC����(�ӿ�ͷ�ļ�)
@brief  PLIC����
@date   2025/01/22
@author �¼�ҫ
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __PLIC_H
#define __PLIC_H

typedef struct{
	uint32_t base_addr; // PLIC����ַ
}PLIC;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void plic_init(PLIC* plic, uint32_t base_addr); // ��ʼ��PLIC

void plic_set_threshold(PLIC* plic, uint32_t threshold); // ����PLIC�ж���ֵ
void plic_enable_interrupt(PLIC* plic, uint32_t source); // ʹ��PLIC�ж�Դ
void plic_disable_interrupt(PLIC * plic, uint32_t source); // ����PLIC�ж�Դ
void plic_set_priority(PLIC * plic, uint32_t source, uint32_t priority); // PLIC�����ж����ȼ�
uint32_t plic_claim_interrupt(PLIC* plic); // PLIC��ȡ�ж�Դ
void plic_complete_interrupt(PLIC* plic, uint32_t source); // PLIC����ж�
