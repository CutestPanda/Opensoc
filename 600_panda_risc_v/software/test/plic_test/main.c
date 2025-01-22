#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/apb_gpio.h"
#include "../../include/apb_timer.h"
#include "../../include/plic.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define TIMER0_BASEADDE 0x40002000

// PLIC基地址
#define PLIC_BASEADDE 0xF0000000

// TIMER0配置
#define TIMER0_PSC 5000 // 预分频系数
#define TIMER0_ATL 2000 // 自动装载值

// 中断号
#define GPIO0_ITR_ID 1 // GPIO0中断号
#define TIMER0_ITR_ID 2 // TIMER0中断号
#define UART0_ITR_ID 3 // UART0中断号

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void gpio0_itr_handler();
static void timer0_itr_handler();

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static ApbTimer timer0;

// PLIC句柄
static PLIC plic;

// 流水灯
const static uint8_t flow_led_out_value[9] = {0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}; // 流水灯样式
static uint8_t flow_led_id = 0; // 流水灯状态
static uint8_t flow_led_style_sel = 0; // 流水灯样式选择
static uint8_t flow_led_div_cnt = 0; // 流水灯分频计数器

// GPIO输入中断
static uint8_t key_falling_detect_cd = 0; // 按键检测消抖计数器
static uint8_t tube_dig_sel = 0; // 当前选中的数码管位号

// 中断事件标志
static uint8_t timer0_period_elapsed = 0; // TIMER0计数溢出标志

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void ext_irq_handler(){
	uint32_t now_itr_id = plic_claim_interrupt(&plic);
	
	switch(now_itr_id){
		case GPIO0_ITR_ID:
			gpio0_itr_handler();
			break;
		case TIMER0_ITR_ID:
			timer0_itr_handler();
			break;
		case UART0_ITR_ID:
			break;
		default:
			break;
	}
	
	plic_complete_interrupt(&plic, now_itr_id);
}

static void gpio0_itr_handler(){
	uint32_t itr_sts = apb_gpio_get_itr_status(&gpio0);
	
	if((itr_sts & 0x00000200) && (!key_falling_detect_cd)){
		apb_gpio_write_pin(&gpio0, 0x00003C00, ~(0x00000400 << tube_dig_sel));
		apb_gpio_write_pin(&gpio0, 0x003FC000, ((uint32_t)0xFF) << 14);
		
		if(tube_dig_sel == 3){
			tube_dig_sel = 0;
		}else{
			tube_dig_sel++;
		}
		
		key_falling_detect_cd = 10;
	}
	
	apb_gpio_clear_itr_flag(&gpio0);
}

static void timer0_itr_handler(){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer0); // 获取中断标志向量
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // 计数溢出中断
		timer0_period_elapsed = 1;
	}
	
	apb_timer_clear_itr_flag(&timer0); // 清除中断标志
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	// 使能外部中断
    // MSIE = 0, MTIE = 0, MEIE = 1
    write_csr(mie, 0x00000800);
	
	// 初始化PLIC
	plic_init(&plic, PLIC_BASEADDE);
	plic_set_threshold(&plic, 0);
	plic_set_priority(&plic, TIMER0_ITR_ID, 1);
	plic_enable_interrupt(&plic, TIMER0_ITR_ID);
	plic_set_priority(&plic, GPIO0_ITR_ID, 2);
	plic_enable_interrupt(&plic, GPIO0_ITR_ID);
	
	// 初始化GPIO
	apb_gpio_init(&gpio0, GPIO0_BASEADDE);
	apb_gpio_set_direction(&gpio0, 0x00000300);
	apb_gpio_enable_itr(&gpio0, 0x00000200);
	
	// 初始化APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(初始化配置结构体)
	
	timer_config.prescale = TIMER0_PSC - 1; // 预分频系数 - 1
	timer_config.auto_load = TIMER0_ATL - 1; // 自动装载值 - 1
	timer_config.chn_n = 0; // 通道数
	timer_config.cap_cmp_sel = CAP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // 捕获/比较选择
	// 比较值
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
	// 边沿检测类型
	timer_config.edge_detect_type[0] = CAP_POS_EDGE;
	timer_config.edge_detect_type[1] = CAP_POS_EDGE;
	timer_config.edge_detect_type[2] = CAP_POS_EDGE;
	timer_config.edge_detect_type[3] = CAP_POS_EDGE;
	// 边沿滤波阈值
	timer_config.edge_filter_th[0] = 0;
	timer_config.edge_filter_th[1] = 0;
	timer_config.edge_filter_th[2] = 0;
	timer_config.edge_filter_th[3] = 0;
	
	init_apb_timer(&timer0, TIMER0_BASEADDE, &timer_config);
	
	// 使能APB-TIMER计数溢出中断
	apb_timer_enable_itr(&timer0, ITR_TIMER_ELAPSED_MASK);
	
	// 启动定时器
	__apb_timer_set_cnt(&timer0, TIMER0_ATL - 1);
	__apb_timer_start(&timer0);
	
    while(1){
		if(timer0_period_elapsed){
			if(key_falling_detect_cd)
				key_falling_detect_cd--;
			
			if(apb_gpio_read_pin(&gpio0) & 0x00000100){
				flow_led_style_sel = 1;
			}else{
				flow_led_style_sel = 0;
			}
			
			flow_led_div_cnt++;
			
			if(flow_led_div_cnt == 5){
				apb_gpio_write_pin(&gpio0, 0x000000FF, (uint32_t)flow_led_out_value[flow_led_style_sel ? (8 - flow_led_id):flow_led_id]);
				
				if(flow_led_id == 8){
					flow_led_id = 0;
				}else{
					flow_led_id++;
				}
				
				flow_led_div_cnt = 0;
			}
			
			timer0_period_elapsed = 0;
		}
    }
}
