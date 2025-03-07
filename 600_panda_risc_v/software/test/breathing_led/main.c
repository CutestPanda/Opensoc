#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/apb_gpio.h"
#include "../../include/apb_timer.h"
#include "../../include/apb_uart.h"
#include "../../include/plic.h"
#include "../../include/xprintf.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define TIMER0_BASEADDE 0x40002000
#define UART0_BASEADDE 0x40003000

// PLIC基地址
#define PLIC_BASEADDE 0xF0000000

// TIMER0配置
#define TIMER0_PSC 50 // 预分频系数
#define TIMER0_ATL 1000 // 自动装载值

// 中断号
#define GPIO0_ITR_ID 1 // GPIO0中断号
#define TIMER0_ITR_ID 2 // TIMER0中断号
#define UART0_ITR_ID 3 // UART0中断号

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static void timer0_itr_handler();

static void uart_putc(uint8_t c);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static ApbTimer timer0;
static ApbUART uart0;

// PLIC句柄
static PLIC plic;

// 中断事件标志
static uint8_t timer0_period_elapsed = 0; // TIMER0计数溢出标志

// LED
static uint8_t led_on = 0; // LED亮(标志)

// 呼吸灯
static uint32_t now_cmp = 0; // 当前的比较值
static uint8_t to_incr_cmp = 1; // 增加/减小比较值(标志)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void ext_irq_handler(){
	uint32_t now_itr_id = plic_claim_interrupt(&plic);
	
	switch(now_itr_id){
		case GPIO0_ITR_ID:
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

static void timer0_itr_handler(){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer0); // 获取中断标志向量
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // 计数溢出中断
		timer0_period_elapsed = 1;
	}
	
	apb_timer_clear_itr_flag(&timer0); // 清除中断标志
}

static void uart_putc(uint8_t c){
	apb_uart_send_byte(&uart0, c);
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
	
	// 初始化GPIO
	apb_gpio_init(&gpio0, GPIO0_BASEADDE);
	apb_gpio_set_direction(&gpio0, 0x00000000);
	
	// 初始化APB-UART
	apb_uart_init(&uart0, UART0_BASEADDE);
	xdev_out(uart_putc); // 重定向字符打印函数
	
	// 初始化APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(初始化配置结构体)
	
	timer_config.prescale = TIMER0_PSC - 1; // 预分频系数 - 1
	timer_config.auto_load = TIMER0_ATL - 1; // 自动装载值 - 1
	timer_config.chn_n = 1; // 通道数
	timer_config.cap_cmp_sel = CMP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // 捕获/比较选择
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
	
	// 启动定时器
	__apb_timer_set_cnt(&timer0, TIMER0_ATL - 1);
	__apb_timer_start(&timer0);
	
    while(1){
		apb_timer_set_cmp(&timer0, APB_TIMER_CH0, now_cmp);
		
		apb_gpio_write_pin(&gpio0, 0x00000001, (uint32_t)led_on);
		
		if(to_incr_cmp){
			if(now_cmp == 1000){
				to_incr_cmp = 0;
			}else{
				now_cmp += 100;
			}
		}else{
			if(now_cmp == 0){
				to_incr_cmp = 1;
			}else{
				now_cmp -= 100;
			}
		}
		
		busy_wait(50 * 1000);
		
		led_on = !led_on;
    }
}
