/************************************************************************************************************************
APB-TIMER驱动(主源文件)
@brief  APB-TIMER驱动
@date   2024/09/21
@author 陈家耀
@eidt   2024/09/21 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../include/apb_timer.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 捕获/比较选择
#define CAP_SEL 0x00 // 捕获
#define CMP_SEL 0x01 // 比较

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化APB-TIMER
@param  timer APB-TIMER(结构体指针)
        base_addr APB-TIMER外设基地址
				config APB-TIMER初始化配置(结构体指针)
@return none
*************************/
void init_apb_timer(ApbTimer* timer, uint32_t base_addr, const ApbTimerConfig* config){
	timer->hardware = (ApbTimerHd*)base_addr;
	
	timer->prescale = config->prescale;
	timer->auto_load = config->auto_load;
	timer->cap_cmp_sel = config->cap_cmp_sel;
	timer->chn_n = config->chn_n;
	
	timer->hardware->prescale = config->prescale;
	timer->hardware->auto_load = config->auto_load;
	timer->hardware->count = config->prescale;
	timer->hardware->ctrl = (((uint32_t)config->cap_cmp_sel) << 8);
	
	for(uint8_t i = 0;i < 4;i++){
		if(((config->cap_cmp_sel >> i) & 0x01) == CAP_SEL){
			// 当前通道选择输入捕获
			timer->hardware->chn_hd[i].cap_config = ((uint32_t)config->edge_filter_th[i]) | 
				(((uint32_t)config->edge_detect_type[i]) << 8);
		}else{
			// 当前通道选择输出比较
			timer->hardware->chn_hd[i].cap_cmp = config->cmp[i];
		}
	}
}

/*************************
@cfg
@public
@brief  APB-TIMER使能中断
@param  timer APB-TIMER(结构体指针)
        itr_en 中断使能向量
@return none
*************************/
void apb_timer_enable_itr(ApbTimer* timer, uint8_t itr_en){
	timer->hardware->itr_en = (((uint32_t)itr_en) << 8) | 0x00000001;
}

/*************************
@cfg
@public
@brief  APB-TIMER除能中断
@param  timer APB-TIMER(结构体指针)
@return none
*************************/
void apb_timer_disable_itr(ApbTimer* timer){
	timer->hardware->itr_en = 0x00000000;
}

/*************************
@sts
@public
@brief  APB-TIMER获取中断状态
@param  timer APB-TIMER(结构体指针)
@return 中断标志向量
*************************/
uint8_t apb_timer_get_itr_status(ApbTimer* timer){
	return (uint8_t)(timer->hardware->itr_flag >> 8);
}

/*************************
@cfg
@public
@brief  APB-TIMER清除中断标志
@param  timer APB-TIMER(结构体指针)
@return none
*************************/
void apb_timer_clear_itr_flag(ApbTimer* timer){
	timer->hardware->itr_flag = 0x00000000;
}

/*************************
@ctrl
@public
@brief  APB-TIMER启动定时器
@param  timer APB-TIMER(结构体指针)
@return none
*************************/
void apb_timer_start(ApbTimer* timer){
	timer->hardware->ctrl = (((uint32_t)timer->cap_cmp_sel) << 8) | 0x00000001;
}

/*************************
@ctrl
@public
@brief  APB-TIMER暂停定时器
@param  timer APB-TIMER(结构体指针)
@return none
*************************/
void apb_timer_stop(ApbTimer* timer){
	timer->hardware->ctrl = (((uint32_t)timer->cap_cmp_sel) << 8);
}

/*************************
@ctrl
@public
@brief  APB-TIMER重置定时器
@param  timer APB-TIMER(结构体指针)
@return none
*************************/
void apb_timer_reset(ApbTimer* timer){
	timer->hardware->count = timer->auto_load;
}

/*************************
@set
@public
@brief  APB-TIMER设置预分频系数
@param  timer APB-TIMER(结构体指针)
		    prescale 预分频系数
@return none
*************************/
void apb_timer_set_prescale(ApbTimer* timer, uint32_t prescale){
	timer->prescale = prescale;
	timer->hardware->prescale = prescale;
}

/*************************
@set
@public
@brief  APB-TIMER设置自动装载值
@param  timer APB-TIMER(结构体指针)
		    auto_load 自动装载值
@return none
*************************/
void apb_timer_set_autoload(ApbTimer* timer, uint32_t auto_load){
	timer->auto_load = auto_load;
	timer->hardware->auto_load = auto_load;
}

/*************************
@set
@public
@brief  APB-TIMER设置计数值
@param  timer APB-TIMER(结构体指针)
		    cnt 计数值
@return none
*************************/
void apb_timer_set_cnt(ApbTimer* timer, uint32_t cnt){
	timer->hardware->count = cnt;
}

/*************************
@set
@public
@brief  APB-TIMER设置某个通道的比较值
@param  timer APB-TIMER(结构体指针)
		    chn_id 通道编号
				cmp 比较值
@return 是否成功
*************************/
int apb_timer_set_cmp(ApbTimer* timer, uint8_t chn_id, uint32_t cmp){
	if((chn_id <= timer->chn_n - 1) && (((timer->cap_cmp_sel >> chn_id) & 0x01) == CMP_SEL)){
		timer->hardware->chn_hd[chn_id].cap_cmp = cmp;
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@set
@public
@brief  APB-TIMER设置某个通道的捕获配置
@param  timer APB-TIMER(结构体指针)
		    chn_id 通道编号
			  edge_detect_type 边沿检测类型
				edge_filter_th 边沿滤波阈值
@return 是否成功
*************************/
int apb_timer_set_cap_config(ApbTimer* timer, uint8_t chn_id, 
	uint8_t edge_detect_type, uint8_t edge_filter_th){
	if((chn_id <= timer->chn_n - 1) && (((timer->cap_cmp_sel >> chn_id) & 0x01) == CAP_SEL)){
		timer->hardware->chn_hd[chn_id].cap_config = ((uint32_t)edge_filter_th) | 
			(((uint32_t)edge_detect_type) << 8);
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@get
@public
@brief  APB-TIMER获取预分频系数
@param  timer APB-TIMER(结构体指针)
@return 预分频系数
*************************/
uint32_t apb_timer_get_prescale(ApbTimer* timer){
	return timer->prescale;
}

/*************************
@get
@public
@brief  APB-TIMER获取自动装载值
@param  timer APB-TIMER(结构体指针)
@return 自动装载值
*************************/
uint32_t apb_timer_get_autoload(ApbTimer* timer){
	return timer->auto_load;
}

/*************************
@get
@public
@brief  APB-TIMER获取计数值
@param  timer APB-TIMER(结构体指针)
@return 当前计数值
*************************/
uint32_t apb_timer_get_cnt(ApbTimer* timer){
	return timer->hardware->count;
}

/*************************
@get
@public
@brief  APB-TIMER获取某个通道的捕获值
@param  chn_id 通道编号
				timer APB-TIMER(结构体指针)
@return 捕获值
*************************/
uint32_t apb_timer_get_cap(ApbTimer* timer, uint8_t chn_id){
	if(chn_id > timer->chn_n - 1){
		return 0x00000000;
	}else{
		return timer->hardware->chn_hd[chn_id].cap_cmp;
	}
}
