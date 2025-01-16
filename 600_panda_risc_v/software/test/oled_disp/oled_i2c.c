#include "oled_i2c.h"
#include "oledfont.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define IIC_SLAVE_ADDR 0x78 // I2C从设备地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbI2C* apb_i2c_handler;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void OLED_WR_Byte(unsigned dat,unsigned cmd);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

//OLED显存总共分为8页
//每页8行，一行128个像素点
//OLED的显存
//存放格式如下.
//[0]0 1 2 3 ... 127 (0~7)行	   
//[1]0 1 2 3 ... 127 (8~15)行	
//[2]0 1 2 3 ... 127 (16~23)行	
//[3]0 1 2 3 ... 127 (24~31)行	
//[4]0 1 2 3 ... 127 (32~39)行	
//[5]0 1 2 3 ... 127 (40~47)行	
//[6]0 1 2 3 ... 127 (48~55)行	
//[7]0 1 2 3 ... 127 (56~63)行			   

/*******************************************************************
 * @name       :void OLED_WR_Byte(unsigned dat,unsigned cmd)
 * @date       :2018-08-27
 * @function   :Write a byte of content to the OLED screen
 * @parameters :dat:Content to be written
                cmd:0-write command
								    1-write data
 * @retvalue   :None
********************************************************************/
void OLED_WR_Byte(unsigned dat,unsigned cmd)
{
	uint8_t send_buf[2] = {cmd ? 0x40:0x00, dat};
	
	apb_i2c_start_wt_trans(apb_i2c_handler, IIC_SLAVE_ADDR, send_buf, 2);
}

/*******************************************************************
 * @name       :void OLED_Set_Pos(unsigned char x, unsigned char y) 
 * @date       :2018-08-27
 * @function   :Set coordinates in the OLED screen
 * @parameters :x:x coordinates
                y:y coordinates
 * @retvalue   :None
********************************************************************/
void OLED_Set_Pos(unsigned char x, unsigned char y) 
{
 	OLED_WR_Byte(YLevel+y,OLED_CMD);
	OLED_WR_Byte((((x+2)&0xf0)>>4)|0x10,OLED_CMD);
	OLED_WR_Byte(((x+2)&0x0f),OLED_CMD); 
}
	   			
/*******************************************************************
 * @name       :void OLED_Clear(unsigned dat)  
 * @date       :2018-08-27
 * @function   :clear OLED screen
 * @parameters :dat:0-Display full black
                    1-Display full white
 * @retvalue   :None
********************************************************************/ 
void OLED_Clear(unsigned dat)  
{ 
	u8 i,n,color;	
	if(dat)
	{
		color = 0xff;
	}
	else
	{
		color = 0;
	}
	for(i=0;i<PAGE_SIZE;i++)  
	{  
		OLED_WR_Byte(YLevel+i,OLED_CMD);    //设置页地址（0~7）
		OLED_WR_Byte(XLevelL,OLED_CMD);      //设置显示位置—列低地址
		OLED_WR_Byte(XLevelH,OLED_CMD);      //设置显示位置—列高地址   
		for(n=0;n<WIDTH;n++)
		{
			OLED_WR_Byte(color,OLED_DATA); 
		}
	}   //更新显示
}

/*******************************************************************
 * @name       :void OLED_Init(void)
 * @date       :2018-08-27
 * @function   :initialise OLED SH1106 control IC
 * @parameters :None
 * @retvalue   :None
********************************************************************/ 				    
void OLED_Init(ApbI2C* i2c)
{
	apb_i2c_handler = i2c;
	
/**************初始化SH1106*****************/	
	for(int i = 0;i < 10 * 1000000;i++);
	
	OLED_WR_Byte(0xAE,OLED_CMD);    /*display off*/       
	OLED_WR_Byte(0x02,OLED_CMD);    /*set lower column address*/       
	OLED_WR_Byte(0x10,OLED_CMD);    /*set higher column address*/     
	OLED_WR_Byte(0x40,OLED_CMD);    /*set display start line*/     
	OLED_WR_Byte(0xB0,OLED_CMD);    /*set page address*/     
	OLED_WR_Byte(0x81,OLED_CMD);    /*contract control*/
	OLED_WR_Byte(0xFF,OLED_CMD);    /*128*/     
	OLED_WR_Byte(0xA1,OLED_CMD);    /*set segment remap*/    
	OLED_WR_Byte(0xA6,OLED_CMD);    /*normal / reverse*/     
	OLED_WR_Byte(0xA8,OLED_CMD);    /*multiplex ratio*/
	OLED_WR_Byte(0x3F,OLED_CMD);    /*duty = 1/64*/     
	OLED_WR_Byte(0xAD,OLED_CMD);    /*set charge pump enable*/
	OLED_WR_Byte(0x8B,OLED_CMD);     /*    0x8B    内供VCC   */     
	OLED_WR_Byte(0x32,OLED_CMD);    /*0X30---0X33  set VPP   8V */     
	OLED_WR_Byte(0xC8,OLED_CMD);    /*Com scan direction*/     
	OLED_WR_Byte(0xD3,OLED_CMD);    /*set display offset*/
	OLED_WR_Byte(0x00,OLED_CMD);   /*   0x20  */     
	OLED_WR_Byte(0xD5,OLED_CMD);    /*set osc division*/
	OLED_WR_Byte(0x80,OLED_CMD);         
	OLED_WR_Byte(0xD9,OLED_CMD);    /*set pre-charge period*/
	OLED_WR_Byte(0x1F,OLED_CMD);    /*0x22*/     
	OLED_WR_Byte(0xDA,OLED_CMD);    /*set COM pins*/
	OLED_WR_Byte(0x12,OLED_CMD);     
	OLED_WR_Byte(0xDB,OLED_CMD);    /*set vcomh*/
	OLED_WR_Byte(0x40,OLED_CMD);                
	OLED_WR_Byte(0xAF,OLED_CMD);    /*display ON*/    
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*******************************************************************
 * @name       :void GUI_Fill(u8 sx,u8 sy,u8 ex,u8 ey,u8 color)
 * @date       :2018-08-27 
 * @function   :fill the specified area
 * @parameters :sx:the bebinning x coordinate of the specified area
                sy:the bebinning y coordinate of the specified area，
								   it must be set 0~7
								ex:the ending x coordinate of the specified area
								ey:the ending y coordinate of the specified area,
								   it must be set 0~7
								color:the color value of the the specified area
								      1-white
											0-black
 * @retvalue   :None
********************************************************************/
void GUI_Fill(u8 sx,u8 sy,u8 ex,u8 ey,u8 color)
{  	
	u8 i,j,dat;			
	u8 width=ex-sx+1; 		//得到填充的宽度
	u8 height=ey-sy+1;		//高度
	if(color)
	{
		dat = 0xff;
	}
	else
	{
		dat = 0;
	}
	for(i=0;i<height;i++)
	{
		OLED_Set_Pos(sx, sy+i); 
		for(j=0;j<width;j++)
		{
				OLED_WR_Byte(dat,OLED_DATA);
		}		
	}
}

/*****************************************************************************
 * @name       :void GUI_ShowChar(u8 x,u8 y,u8 chr,u8 Char_Size,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display a single English character
 * @parameters :x:the bebinning x coordinate of the Character display position
                y:the bebinning y coordinate of the Character display position,
								  it must be set 0~7
								chr:the ascii code of display character(0~94)
								Char_Size:the size of display character(8,16)
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/ 
void GUI_ShowChar(u8 x,u8 y,u8 chr,u8 Char_Size,u8 mode)
{      	
	  unsigned char c=0,i=0,j=0;	
		c=chr-' ';//得到偏移后的值			
		if(x>WIDTH-1)
		{
			x=0;
			y=y+2;
		}
		if(Char_Size ==16)
		{
		  for(j=0;j<2;j++)
			{
				OLED_Set_Pos(x,y+j);
				for(i=0;i<8;i++)
				{
					if(mode)
					{
						OLED_WR_Byte(F8X16[c*16+i+j*8],OLED_DATA);
					}
					else
					{
						OLED_WR_Byte(~(F8X16[c*16+i+j*8]),OLED_DATA);
					}
				}
			}
		 }
		 else 
		 {	
				OLED_Set_Pos(x,y);
				for(i=0;i<6;i++)
				{
				  if(mode)
					{
						OLED_WR_Byte(F6x8[c][i],OLED_DATA);
					}
					else
					{
						OLED_WR_Byte(~(F6x8[c][i]),OLED_DATA);
					}
				}
		}
}

/*****************************************************************************
 * @name       :void GUI_ShowString(u8 x,u8 y,u8 *chr,u8 Char_Size,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display English string
 * @parameters :x:the bebinning x coordinate of the English string
                y:the bebinning y coordinate of the English string
								  it must be set 0~7
								chr:the start address of the English string
								Char_Size:the size of display character
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/   	  
void GUI_ShowString(u8 x,u8 y,u8 *chr,u8 Char_Size,u8 mode)
{
	unsigned char j=0,csize;
	if(Char_Size == 16)
  {
	  csize = Char_Size/2;
	}
  else if(Char_Size == 8)
  {
	  csize = Char_Size/2+2;
	}
	else
	{
		return;
	}
	while (chr[j]!='\0')
	{		
		GUI_ShowChar(x,y,chr[j],Char_Size,mode);
		x+=csize;
		if(x>120)
		{
			x=0;
			y+=Char_Size/8;
		}
		j++;
	}
}

/*****************************************************************************
 * @name       :u32 mypow(u8 m,u8 n)
 * @date       :2018-08-27 
 * @function   :get the nth power of m (internal call)
 * @parameters :m:the multiplier
                n:the power
 * @retvalue   :the nth power of m
******************************************************************************/ 
static u32 mypow(u8 m,u8 n)
{
	u32 result=1;	 
	while(n--)result*=m;    
	return result;
}

/*****************************************************************************
 * @name       :void GUI_ShowNum(u8 x,u8 y,u32 num,u8 len,u8 Size,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display number
 * @parameters :x:the bebinning x coordinate of the number
                y:the bebinning y coordinate of the number
								  it must be set 0~7
								num:the number(0~4294967295)
								len:the length of the display number
								Size:the size of display number
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/  			 
void GUI_ShowNum(u8 x,u8 y,u32 num,u8 len,u8 Size,u8 mode)
{         	
	u8 t,temp;
	u8 enshow=0,csize;
  if(Size == 16)
  {
	  csize = Size/2;
	}
  else if(Size == 8)
  {
	  csize = Size/2+2;
	} 	
	else
	{
		return;
	}
	for(t=0;t<len;t++)
	{
		temp=(num/mypow(10,len-t-1))%10;
		if(enshow==0&&t<(len-1))
		{
			if(temp==0)
			{
				GUI_ShowChar(x+csize*t,y,' ',Size,mode);
				continue;
			}
			else 
			{
				enshow=1; 
		 	}
		}
	 	GUI_ShowChar(x+csize*t,y,temp+'0',Size,mode); 
	}
}  

/*****************************************************************************
 * @name       :void GUI_ShowFont16(u8 x,u8 y,u8 *s,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display a single 16x16 Chinese character
 * @parameters :x:the bebinning x coordinate of the Chinese character
                y:the bebinning y coordinate of the Chinese character
								  it must be set 0~7
								s:the start address of the Chinese character
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/ 
void GUI_ShowFont16(u8 x,u8 y,u8 *s,u8 mode)
{
	u8 i,j,k,tmp;
	u16 num;
	num = sizeof(cfont16)/sizeof(typFNT_GB16);
  for(i=0;i<num;i++)
	{
		if((cfont16[i].Index[0]==*s)&&(cfont16[i].Index[1]==*(s+1)))
		{
			for(k=0;k<2;k++)
			{
			  OLED_Set_Pos(x,y+k);
				for(j=0;j<16;j++)
				{
					if(mode)
					{
						tmp = cfont16[i].Msk[j+k*16];
					}
					else
					{
						tmp = ~(cfont16[i].Msk[j+k*16]);
					}
					OLED_WR_Byte(tmp,OLED_DATA);
				}
			}	
			break;
		}	
	}
}

/*****************************************************************************
 * @name       :void GUI_ShowFont24(u8 x,u8 y,u8 *s,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display a single 24x24 Chinese character
 * @parameters :x:the bebinning x coordinate of the Chinese character
                y:the bebinning y coordinate of the Chinese character
								  it must be set 0~7
								s:the start address of the Chinese character
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/ 
void GUI_ShowFont24(u8 x,u8 y,u8 *s,u8 mode)
{
	u8 i,j,k,tmp;
	u16 num;
	num = sizeof(cfont24)/sizeof(typFNT_GB24);
  for(i=0;i<num;i++)
	{
		if((cfont24[i].Index[0]==*s)&&(cfont24[i].Index[1]==*(s+1)))
		{
			for(k=0;k<3;k++)
			{
			  OLED_Set_Pos(x,y+k);
				for(j=0;j<24;j++)
				{
					if(mode)
					{
						tmp = cfont24[i].Msk[j+k*24];
					}
					else
					{
						tmp = ~(cfont24[i].Msk[j+k*24]);
					}
					OLED_WR_Byte(tmp,OLED_DATA);
				}
			}	
			break;
		}	
	}
}

/*****************************************************************************
 * @name       :void GUI_ShowFont32(u8 x,u8 y,u8 *s,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display a single 32x32 Chinese character
 * @parameters :x:the bebinning x coordinate of the Chinese character
                y:the bebinning y coordinate of the Chinese character
								  it must be set 0~7
								s:the start address of the Chinese character
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/ 
void GUI_ShowFont32(u8 x,u8 y,u8 *s,u8 mode)
{
	u8 i,j,k,tmp;
	u16 num;
	num = sizeof(cfont32)/sizeof(typFNT_GB32);
  for(i=0;i<num;i++)
	{
		if((cfont32[i].Index[0]==*s)&&(cfont32[i].Index[1]==*(s+1)))
		{
			for(k=0;k<4;k++)
			{
			  OLED_Set_Pos(x,y+k);
				for(j=0;j<32;j++)
				{
					if(mode)
					{
						tmp = cfont32[i].Msk[j+k*32];
					}
					else
					{
						tmp = ~(cfont32[i].Msk[j+k*32]);
					}
					OLED_WR_Byte(tmp,OLED_DATA);
				}
			}	
			break;
		}	
	}
}

/*****************************************************************************
 * @name       :void GUI_ShowCHinese(u8 x,u8 y,u8 hsize,u8 *str,u8 mode)
 * @date       :2018-08-27 
 * @function   :Display Chinese strings
 * @parameters :x:the bebinning x coordinate of the Chinese strings
                y:the bebinning y coordinate of the Chinese strings
								  it must be set 0~7
								size:the size of Chinese strings
								str:the start address of the Chinese strings
								mode:0-white background and black character
								     1-black background and white character
 * @retvalue   :None
******************************************************************************/	   		   
void GUI_ShowCHinese(u8 x,u8 y,u8 hsize,u8 *str,u8 mode)
{ 
	while(*str!='\0')
	{
		if(hsize == 16)
		{
			GUI_ShowFont16(x,y,str,mode);
		}
		else if(hsize == 24)
		{
			GUI_ShowFont24(x,y,str,mode);
		}
		else if(hsize == 32)
		{
			GUI_ShowFont32(x,y,str,mode);
		}
		else
		{
			return;
		}
		x+=hsize;
		if(x>WIDTH-hsize)
		{
			x=0;
			y+=hsize/8;
		}
		str+=2;
	}			
}
