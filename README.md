# Opensoc<br>
![LOGO](./img/logo.png)<br>
包含了SOC设计中的通用IP，如外设与控制器、总线结构、基础、DMA、验证等<br>
__本项目持续更新中__<br>
__欢迎交流学习__<br>
__欢迎贡献您的IP(参与开发请fork)__<br>
## 贡献者<br>
|姓名      | 单位      | 联系方式 | 
|:-------- |:----------|:--------|
|__陈家耀__  |电子科技大学 |2257691535@qq.com  |
## 已发布的IP<br>
(1)__外设与控制器__<br>
APB-GPIO<br>
APB-UART<br>
APB-I2C<br>
APB-TIMER<br>
通用FSMC控制器<br>
APB-音频播放器<br>
通用BRAM控制器<br>
AXI-SDRAM控制器<br>
通用SDIO控制器<br>
(2)__总线结构__<br>
AHB/AXI-APB桥<br>
(3)__基础__<br>
AXIS-位宽变换<br>
AXIS寄存器片<br>
AXIS数据FIFO<br>
基于RAM/FF的移位寄存器<br>
(4)__DMA__<br>
AXI-帧缓存(视频专用DMA)<br>
(5)__验证__<br>
AMBA总线基本验证组件<br>
## 待整理的IP<br>
APB-SPI<br>
AXI-通用卷积加速器<br>
AXI-最大池化单元<br>
## 正在开发的IP<br>
(1)__DMA__<br>
AXI-通用DMA引擎<br>
(2)__CPU__<br>
RV32处理器(I[M])<br>
## 准备开发的IP<br>
AXI-DDR3控制器<br>
AXI-系统缓存<br>
## 文件结构<br>
XXX_IP<br>
&emsp;&emsp;[constraint]<br>
&emsp;&emsp;doc<br>
&emsp;&emsp;[firmware]<br>
&emsp;&emsp;&emsp;&emsp;examples<br>
&emsp;&emsp;rtl<br>
&emsp;&emsp;[tb]<br>
&emsp;&emsp;[其他]<br>
<br>
注:<br>
&emsp;&emsp;constraint -> 时序约束<br>
&emsp;&emsp;doc -> 使用说明文档<br>
&emsp;&emsp;firmware -> 驱动<br>
&emsp;&emsp;rtl -> RTL设计源码<br>
&emsp;&emsp;tb -> 测试平台<br>
## 修订<br>
|版本      | 日期      | 修订人 |  内容 | 
|:-------- |:----------|:--------|:--------|
|alpha0.40  |2024.09.06 |陈家耀  |上传Opensoc项目|
|alpha0.50  |2024.09.07 |陈家耀  |发布了通用SDIO控制器|
|alpha0.55  |2024.09.11 |陈家耀  |发布了AXIS位宽变换|
|alpha0.56  |2024.09.12 |陈家耀  |发布了基于RAM/FF的移位寄存器|
|alpha0.60  |2024.09.16 |陈家耀  |发布了AXI帧缓存|
|alpha0.62  |2024.09.18 |陈家耀  |发布了AXIS数据fifo|
|alpha0.65  |2024.09.21 |陈家耀  |发布了APB-TIMER|
