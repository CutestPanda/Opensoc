## 简介
小胖达MCU是一种**基于RISC-V**、**完全开源**、**设计严谨**、**结构清晰**的处理器核，适用于交互、控制等任务，它具有以下特性：  

 - RV32 I[M]（EBREAK指令除外）
 - 支持中断/异常
 - 可运行C程序
 - 采用ICB总线
 - 配备内置ITCM、DTCM、PLIC和CLINT的最小处理器系统

## 配置编译环境
1.下载MAKE工具和GNU工具链（[百度云链接](https://pan.baidu.com/s/1Wq-isumnnuQNxXdvCApr0g?pwd=1234)）  
2.安装MAKE工具  
将GNU MCU Eclipse.zip解压到任意文件夹下，在GNU MCU Eclipse/Build Tools/2.11-20180428-1604/bin下找到make.exe，并添加系统环境变量。  
比如，我们直接解压到D盘，那么在D:/GNU MCU Eclipse/Build Tools/2.11-20180428-1604/bin可以找到make.exe。  
![说明1](../img/panda_risc_v_1.png)  
然后，添加系统环境变量。  
![说明2](../img/panda_risc_v_2.png)  
3.安装GNU工具链  
将gnu-mcu-eclipse-riscv-none-gcc-8.2.0-2.2-20190521-0004-win64.zip解压到**600_panda_risc_v/tools**下。  

## 编译C程序
请确保已经安装好python解释器，并将python.exe所在目录添加到了环境变量里。  
在**600_panda_risc_v/scripts**下，打开命令行终端，输入：  
`` python .\compile.py --target flow_led ``  
等待出现"请按任意键继续. . ."后，键入`` ENTER ``，并退出终端。  
> 生成的flow_led.txt是十六进制的机器码文本文件，flow_led.bin是二进制的机器码文件，flow_led.dump是汇编指令文件。  
其中，flow_led对应**600_panda_risc_v/software/test**下的软件项目**flow_led**。  

## 创建软件项目
1.先在**600_panda_risc_v/scripts**下，打开命令行终端，输入：  
`` python .\gen_makefile.py --target your_prj_name ``  
2.然后在**600_panda_risc_v/software/test**下新建文件夹**your_prj_name**，把刚才创建的Makefile复制进去。  
3.在**600_panda_risc_v/software/test/your_prj_name**下编写若干.c和.h。  
> 软件项目引用了**600_panda_risc_v/software/lib**下的驱动或工具程序，其使用的外设都能在Opensoc仓库里找到。  

## 搭建硬件工程
测评SOC的所有源码都在**600_panda_risc_v/fpga/panda_soc_eva**下，  
请修改**imem_init_file**参数为boot_rom.txt所在的路径（在**600_panda_risc_v/fpga**下），注意修改PLL的例化。  
在SOC测评工程中，PLL输出时钟的频率是**50MHz**。  

#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|PLIC|0xF000_0000~0xF03F_FFFF|4MB|
|CLINT|0xF400_0000~0xF7FF_FFFF|64MB|

#### <center>I/O表</center>
|I/O|说明|
|---|---|
|osc_clk|外部晶振时钟输入|
|ext_resetn|外部复位输入, 低有效|
|boot|编程模式, 拨码开关, 1'b0 -> UART编程, 1'b1 -> 正常运行|
|gpio0[7:0]|LED|
|gpio0[9:8]|拨码开关|
|gpio0[13:10]|数码管位码|
|gpio0[21:14]|数码管段码|
|i2c0_scl|OLED显示屏SCL|
|i2c0_sda|OLED显示屏SDA|
|uart0_tx|串口发送端|
|uart0_rx|串口接收端|

#### <center>外部中断表</center>
|中断号|说明|
|---|---|
|0|不可用|
|1|GPIO0中断|
|2|TIMER0中断|
|3|UART0中断|

指令存储器的低2KB用作bootrom。  
小胖达risc-v最小系统（见panda_risc_v_min_proc_sys.v）接入了63位的外部中断向量（ext_itr_req_vec[62:0]），  
ext_itr_req_vec[0]对应中断号1，ext_itr_req_vec[1]对应中断号2，以此类推。  

> 在**600_panda_risc_v/fpga/vivado_prj**下提供了基于ZYNQ7020的示例Vivado工程。

## 下载与调试
目前只支持UART编程烧录。  

#### UART编程烧录
请确保当前python环境已经安装了pyserial库，否则需要打开命令行终端并执行：  
`` pip install pyserial ``  
将boot引脚对应的拨码开关拨到**低电平**，此时CPU运行bootrom程序。  
将编译产生的.bin文件复制到**600_panda_risc_v/scripts**下，然后在scripts文件夹打开命令行终端，输入：  
`` python .\uart_prog.py ``  
然后，按提示打开串口（必须要输入打开的串口名才能打开，如"COM10"），输入.bin文件的路径，等待烧录完成。  
![说明3](../img/panda_risc_v_3.png)  
最后，将boot引脚对应的拨码开关拨到**高电平**，复位CPU，即可见CPU运行烧录的程序。  
> 如果提示无法接收到编程应答，那么可以在打开串口后（输入了要连接的串口后），按一下外部复位引脚。  
