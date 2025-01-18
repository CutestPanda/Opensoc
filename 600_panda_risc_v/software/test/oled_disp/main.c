#include <stdint.h>

#include "../../include/utils.h"
#include "../../include/apb_gpio.h"
#include "../../include/apb_i2c.h"

#include "oled_i2c.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设基地址
#define GPIO0_BASEADDE 0x40000000
#define I2C0_BASEADDE 0x40001000

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbGPIO gpio0;
static ApbI2C i2c0;

// 流水灯
const static uint8_t flow_led_out_value[4][9] = 
	{
		{0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01, 0x00}, 
		{0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80}, 
		{0x00, 0x18, 0x3C, 0x7E, 0xFF, 0x7E, 0x3C, 0x18, 0x00}, 
		{0xFF, 0x7E, 0x3C, 0x18, 0x00, 0x18, 0x3C, 0x7E, 0xFF}
	}; // 流水灯样式
static uint8_t flow_led_id = 0; // 流水灯状态
static uint8_t flow_led_style_sel = 0; // 流水灯样式选择
static uint16_t oled_disp_num = 0; // OLED显示的数字

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	apb_gpio_init(&gpio0, GPIO0_BASEADDE); // 初始化GPIO0
	apb_gpio_set_direction(&gpio0, 0xFFFFFF00); // 设置GPIO0方向
	
	apb_i2c_init(&i2c0, I2C0_BASEADDE); // 初始化I2C0
	apb_i2c_config_params(&i2c0, 1, 1, 31); // 配置I2C0运行时参数
	
	// 初始化OLED
	OLED_Init(&i2c0);
	OLED_Clear(0);
	
	// OLED显示测试
	GUI_ShowString(0, 0, (u8*)"Panda", 16, 1);
	
    while(1){
        apb_gpio_write_pin(&gpio0, 0x000000FF, (uint32_t)flow_led_out_value[flow_led_style_sel][flow_led_id]);
		
		for(int i = 0;i < 600000;i++);
		
		flow_led_style_sel = (uint8_t)((apb_gpio_read_pin(&gpio0) & 0x00000300) >> 8);
		
		GUI_ShowNum(0, 4, (u32)oled_disp_num, 3, 16, 1);
		
		if(oled_disp_num == 199){
			oled_disp_num = 0;
		}else{
			oled_disp_num++;
		}
		
		if(flow_led_id == 8){
			flow_led_id = 0;
		}else{
			flow_led_id++;
		}
    }
}
