#include "../../include/apb_i2c.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __OLED_H
#define __OLED_H

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;

//--------------OLED参数定义---------------------
#define PAGE_SIZE    8
#define XLevelL		   0x02
#define XLevelH		   0x10
#define YLevel       0xB0
#define	Brightness	 0xFF 
#define WIDTH 	     128
#define HEIGHT 	     64	

//-------------写命令和数据定义-------------------
#define OLED_CMD     0	//写命令
#define OLED_DATA    1	//写数据 

//OLED控制用函数
void OLED_Set_Pos(unsigned char x, unsigned char y);
void OLED_Init(ApbI2C* i2c);
void OLED_Clear(unsigned dat);

// GUI
void GUI_Fill(u8 sx,u8 sy,u8 ex,u8 ey,u8 color);
void GUI_ShowChar(u8 x,u8 y,u8 chr,u8 Char_Size,u8 mode);
void GUI_ShowNum(u8 x,u8 y,u32 num,u8 len,u8 Size,u8 mode);
void GUI_ShowString(u8 x,u8 y,u8 *chr,u8 Char_Size,u8 mode);
void GUI_ShowFont16(u8 x,u8 y,u8 *s,u8 mode);
void GUI_ShowFont24(u8 x,u8 y,u8 *s,u8 mode);
void GUI_ShowFont32(u8 x,u8 y,u8 *s,u8 mode);
void GUI_ShowCHinese(u8 x,u8 y,u8 hsize,u8 *str,u8 mode);
#endif
