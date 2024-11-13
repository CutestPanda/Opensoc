/************************************************************************************************************************
全局中断控制器操作库
@brief  实现了对全局中断控制器的初始化和使能操作
              实现了软中断的初始化和使能操作
@date   2022/09/27
@author 陈家耀
@eidt   none
************************************************************************************************************************/

#include "gic.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void soft_intr_handler(void* CallbackRef);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

Soft_itr_handler soft_itr_hanlder_ptr = NULL; //软中断处理函数(指针)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化全局中断控制器(GIC)
@param  gic_ins_ptr GIC结构体(指针)
        gic_device_id GIC器件ID 如:XPAR_SCUGIC_SINGLE_DEVICE_ID
@return 是否成功
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
@brief  连接并配置中断
@param  gic_ins_ptr GIC结构体(指针)
		callback_ref 回调句柄
        handler 中断服务函数(指针) 参考函数原型:void intr_handler(void *callback_ref);
        itr_NO 中断号 如:61
        priority 中断优先级(越大越低) 可选:0~31 典型:20
        trigger 触发类型 可选:ITR_HIGH_LEVEL_TG|ITR_RISING_EDGE_TG
@return 是否成功
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
@brief  初始化软件中断
@param  gic_ins_ptr GIC结构体(指针)
        handler 软中断处理函数(指针) 参考函数原型:void soft_itr_handler(XScuGic* gic_ins_ptr);
        soft_itr_id 软中断号 范围:0~15
@return 是否成功
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
@brief  软件中断服务函数
@param  CallbackRef 中断句柄
@return 是否成功
*************************/
void soft_intr_handler(void* CallbackRef){
	if(soft_itr_hanlder_ptr != NULL){
		soft_itr_hanlder_ptr((XScuGic*)CallbackRef);
	}
}
