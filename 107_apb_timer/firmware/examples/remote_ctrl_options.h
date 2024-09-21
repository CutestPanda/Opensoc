/*****************************************
库配置头文件
*****************************************/

#define REMOTE_CONTROL_COUNTER 1000000 // 红外遥控对应timer的自动装载值
#define REMOTE_CTRL_CHANNEL APB_TIMER_CH0  // 用于输入捕获的定时器通道
#define CAPTURE_TIMEOUT 20 // 红外遥控检测阈值(以定时器计数周期计)
#define CAPTURE_ERR_TH 80 // 捕获误差阈值
// #define NEED_C // 需要校验
