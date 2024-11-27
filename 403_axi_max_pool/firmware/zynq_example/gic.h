/************************************************************************************************************************
全局中断控制器操作库(接口头文件)
@brief  实现了对全局中断控制器的初始化、使能
@date   2022/09/27
@author 陈家耀
************************************************************************************************************************/

#include "xscugic.h"
#include "xil_exception.h"
#include "xparameters.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef MY_GIC
	#define MY_GIC
	//软中断处理函数
	typedef void (*Soft_itr_handler)(XScuGic* gic_ins_ptr);
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

//中断触发类型(高电平|上升沿)
#define ITR_HIGH_LEVEL_TG 0x01
#define ITR_RISING_EDGE_TG 0x03

//GIC使能中断
#define __GIC_EN_itr(gic_ins_ptr, itr_id) XScuGic_Enable(gic_ins_ptr, itr_id)

//GIC失能中断
#define __GIC_DIS_itr(gic_ins_ptr, itr_id) XScuGic_Disable(gic_ins_ptr, itr_id)

//触发软件中断(soft_itr_id:软中断号->范围0~15 cpu_id:CPU编号->如XSCUGIC_SPI_CPU0_MASK)
#define __SEND_soft_itr(gic_ins_ptr, soft_itr_id, cpu_id) XScuGic_SoftwareIntr(gic_ins_ptr, soft_itr_id,\
	cpu_id)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int init_gic(XScuGic* gic_ins_ptr, u8 gic_device_id); //初始化全局中断控制器(GIC)
int gic_conn_config_itr(XScuGic* gic_ins_ptr, void* callback_ref, Xil_InterruptHandler handler,
		u32 itr_NO, u8 priority, u8 trigger); //连接并配置中断
int init_soft_intr(XScuGic* gic_ins_ptr, Soft_itr_handler handler, u16 soft_itr_id); //初始化软件中断
