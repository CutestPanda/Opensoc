/************************************************************************************************************************
ȫ���жϿ�����������
@brief  ʵ���˶�ȫ���жϿ������ĳ�ʼ����ʹ�ܲ���
              ʵ�������жϵĳ�ʼ����ʹ�ܲ���
@date   2022/09/27
@author �¼�ҫ
@eidt   none
************************************************************************************************************************/

#include "gic.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void soft_intr_handler(void* CallbackRef);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

Soft_itr_handler soft_itr_hanlder_ptr = NULL; //���жϴ�����(ָ��)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��ȫ���жϿ�����(GIC)
@param  gic_ins_ptr GIC�ṹ��(ָ��)
        gic_device_id GIC����ID ��:XPAR_SCUGIC_SINGLE_DEVICE_ID
@return �Ƿ�ɹ�
*************************/
int init_gic(XScuGic* gic_ins_ptr, u8 gic_device_id){
	XScuGic_Config* IntcConfig = XScuGic_LookupConfig(gic_device_id);
	if (IntcConfig == NULL) {
		return XST_FAILURE;
	}

	if (XScuGic_CfgInitialize(gic_ins_ptr, IntcConfig, IntcConfig->CpuBaseAddress) != XST_SUCCESS) {
		return XST_FAILURE;
	}

	Xil_ExceptionInit();
	Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler) XScuGic_InterruptHandler,
			gic_ins_ptr);
	Xil_ExceptionEnable();

	return XST_SUCCESS;
}

/*************************
@init
@public
@brief  ���Ӳ������ж�
@param  gic_ins_ptr GIC�ṹ��(ָ��)
		callback_ref �ص����
        handler �жϷ�����(ָ��) �ο�����ԭ��:void intr_handler(void *callback_ref);
        itr_NO �жϺ� ��:61
        priority �ж����ȼ�(Խ��Խ��) ��ѡ:0~31 ����:20
        trigger �������� ��ѡ:ITR_HIGH_LEVEL_TG|ITR_RISING_EDGE_TG
@return �Ƿ�ɹ�
*************************/
int gic_conn_config_itr(XScuGic* gic_ins_ptr, void* callback_ref, Xil_InterruptHandler handler,
		u32 itr_NO, u8 priority, u8 trigger){
	XScuGic_SetPriorityTriggerType(gic_ins_ptr, itr_NO, priority << 3, trigger);
	if(XScuGic_Connect(gic_ins_ptr, itr_NO, handler, callback_ref)
			!= XST_SUCCESS){
		return XST_FAILURE;
	}
	XScuGic_Enable(gic_ins_ptr, itr_NO);

	return XST_SUCCESS;
}

/*************************
@init
@public
@brief  ��ʼ������ж�
@param  gic_ins_ptr GIC�ṹ��(ָ��)
        handler ���жϴ�����(ָ��) �ο�����ԭ��:void soft_itr_handler(XScuGic* gic_ins_ptr);
        soft_itr_id ���жϺ� ��Χ:0~15
@return �Ƿ�ɹ�
*************************/
int init_soft_intr(XScuGic* gic_ins_ptr, Soft_itr_handler handler, u16 soft_itr_id){
	if(XScuGic_Connect(gic_ins_ptr, soft_itr_id,
	(Xil_ExceptionHandler)soft_intr_handler, (void *)gic_ins_ptr) != XST_SUCCESS){
        return XST_FAILURE;
    }

	soft_itr_hanlder_ptr = handler;

	return XST_SUCCESS;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@handler
@private
@brief  ����жϷ�����
@param  CallbackRef �жϾ��
@return �Ƿ�ɹ�
*************************/
void soft_intr_handler(void* CallbackRef){
	if(soft_itr_hanlder_ptr != NULL){
		soft_itr_hanlder_ptr((XScuGic*)CallbackRef);
	}
}
