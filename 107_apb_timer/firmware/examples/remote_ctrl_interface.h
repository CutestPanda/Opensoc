/*****************************************
库接口头文件
*****************************************/


#include "apb_timer.h"

void remote_ctrl_init(ApbTimer* timer); // 初始化函数
void remote_ctrl_timer_execute(void); // 定时器计数溢出操作函数
void remote_ctrl_IC_execute(ApbTimer* timer); // 边沿捕获操作函数
