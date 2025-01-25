# Opensoc
![LOGO](./img/logo.png)  
包含了SOC设计中的通用IP，如外设与控制器、总线结构、基础、DMA、验证、CPU核等  
__本项目持续更新中__  
__欢迎交流学习__  
__欢迎贡献您的IP(参与开发请fork)__  

## 贡献者
|姓名      | 单位      | 联系方式 | 
|:-------- |:----------|:--------|
|__陈家耀__  |电子科技大学 |2257691535@qq.com  |

## 已发布的IP
(1)__外设与控制器__  
APB-GPIO  
APB-UART  
APB-I2C  
APB-TIMER  
通用FSMC控制器  
APB-音频播放器  
通用BRAM控制器  
AXI-SDRAM控制器  
通用SDIO控制器  
(2)__总线结构__  
AHB/AXI-APB桥  
(3)__基础__  
AXIS-位宽变换  
AXIS寄存器片  
AXIS数据FIFO  
基于RAM/FF的移位寄存器  
(4)__DMA__  
AXI-帧缓存(视频专用DMA)  
(5)__验证__  
AMBA总线基本验证组件  
(6)__CPU__  
小胖达RV32 I[M]  

## 待整理的IP
APB-SPI  
AXI-通用卷积加速器  
AXI-最大池化单元  
AXI-上采样单元  
AXIS-浮点计算单元  

## 正在开发的IP
AXI-通用DMA引擎  

## 准备开发的IP
AXI-DDR3控制器  
AXI-系统缓存  

## 文件结构
XXX_IP  
&emsp;&emsp;[constraint]  
&emsp;&emsp;doc  
&emsp;&emsp;[firmware]  
&emsp;&emsp;&emsp;&emsp;examples  
&emsp;&emsp;rtl  
&emsp;&emsp;[tb]  
&emsp;&emsp;[其他]  
  
注:  
&emsp;&emsp;constraint -> 时序约束  
&emsp;&emsp;doc -> 使用说明文档  
&emsp;&emsp;firmware -> 驱动  
&emsp;&emsp;rtl -> RTL设计源码  
&emsp;&emsp;tb -> 测试平台  

## 修订
|版本      | 日期      | 修订人 |  内容 | 
|:-------- |:----------|:--------|:--------|
|alpha0.40  |2024.09.06 |陈家耀  |上传Opensoc项目|
|alpha0.50  |2024.09.07 |陈家耀  |发布了通用SDIO控制器|
|alpha0.55  |2024.09.11 |陈家耀  |发布了AXIS位宽变换|
|alpha0.56  |2024.09.12 |陈家耀  |发布了基于RAM/FF的移位寄存器|
|alpha0.60  |2024.09.16 |陈家耀  |发布了AXI帧缓存|
|alpha0.62  |2024.09.18 |陈家耀  |发布了AXIS数据fifo|
|alpha0.65  |2024.09.21 |陈家耀  |发布了APB-TIMER|
|alpha0.70  |2025.01.20 |陈家耀  |发布了小胖达RV32 I[M]|
