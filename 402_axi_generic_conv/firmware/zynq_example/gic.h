/************************************************************************************************************************
ȫ���жϿ�����������(�ӿ�ͷ�ļ�)
@brief  ʵ���˶�ȫ���жϿ������ĳ�ʼ����ʹ��
@date   2022/09/27
@author �¼�ҫ
************************************************************************************************************************/

#include "xscugic.h"
#include "xil_exception.h"
#include "xparameters.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef MY_GIC
	#define MY_GIC
	//���жϴ�����
	typedef void (*Soft_itr_handler)(XScuGic* gic_ins_ptr);
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

//�жϴ�������(�ߵ�ƽ|������)
#define ITR_HIGH_LEVEL_TG 0x01
#define ITR_RISING_EDGE_TG 0x03

//GICʹ���ж�
#define __GIC_EN_itr(gic_ins_ptr, itr_id) XScuGic_Enable(gic_ins_ptr, itr_id)

//GICʧ���ж�
#define __GIC_DIS_itr(gic_ins_ptr, itr_id) XScuGic_Disable(gic_ins_ptr, itr_id)

//��������ж�(soft_itr_id:���жϺ�->��Χ0~15 cpu_id:CPU���->��XSCUGIC_SPI_CPU0_MASK)
#define __SEND_soft_itr(gic_ins_ptr, soft_itr_id, cpu_id) XScuGic_SoftwareIntr(gic_ins_ptr, soft_itr_id,\
	cpu_id)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int init_gic(XScuGic* gic_ins_ptr, u8 gic_device_id); //��ʼ��ȫ���жϿ�����(GIC)
int gic_conn_config_itr(XScuGic* gic_ins_ptr, void* callback_ref, Xil_InterruptHandler handler,
		u32 itr_NO, u8 priority, u8 trigger); //���Ӳ������ж�
int init_soft_intr(XScuGic* gic_ins_ptr, Soft_itr_handler handler, u16 soft_itr_id); //��ʼ������ж�
