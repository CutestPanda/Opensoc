## 简介
小胖达MCU是一种**基于RISC-V**、**完全开源**、**设计严谨**、**结构清晰**的处理器核，适用于交互、控制等任务，它具有以下特性：  

 - RV32 I[M]
 - 三级流水线（取指 -> 译码 -> 派遣+执行+写回）
 - 采用简单的静态分支预测（BTFN）
 - 支持单周期指令的数据旁路
 - 支持长指令（乘除法、加载/存储）乱序写回，支持后序单周期指令比前序长指令先写回
 - 采用ICB总线
 - 可运行C程序
 - 支持中断/异常，可处理多达63个外部中断
 - 在最小处理器系统中配备ITCM、DTCM、PLIC和CLINT
 - 支持JTAG在线调试，支持UART编程烧录
 - 易于移植到FPGA
 - 支持Eclipse IDE

小胖达MCU尚未支持以下特性：  

 - ICache和DCache

## 文件结构
**doc**: 设计文档、参考手册  
**fpga**: 测评SOC源码、Vivado工程  
**rtl**: 处理器核的RTL代码  
**scripts**: 用于编译、UART编程烧录的脚本  
**software**: 外设驱动、软件程序示例  
**tb**: 测试平台  
**tb/tb_panda_risc_v**下提供了本处理器核的仿真平台。  
**tools**: GNU工具链，openocd  

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
4.安装Python  
安装好Python并将python.exe所在目录添加到环境变量里。  
然后，为当前python环境安装pyserial库，打开命令行终端并执行：  
`` pip install pyserial ``  
> 作者在测试时使用的是python3.12。  

## 编译C程序
在**600_panda_risc_v/scripts**下，打开命令行终端，输入：  
`` python .\compile.py --target flow_led ``  
等待出现"请按任意键继续. . ."后，键入`` ENTER ``，并退出终端。  
> 生成的flow_led.txt是十六进制的机器码文本文件，flow_led.bin是二进制的机器码文件，flow_led.dump是汇编指令文件。  
其中，flow_led对应**600_panda_risc_v/software/test**下的软件项目**flow_led**。  

## 创建软件项目
1.先在**600_panda_risc_v/scripts**下，打开命令行终端，输入：  
`` python .\gen_makefile.py --target your_prj_name --debug ``  
其中，--debug表示在需要在.elf文件中添加调试信息，这是可选的。  
2.然后在**600_panda_risc_v/software/test**下新建文件夹**your_prj_name**，把刚才创建的Makefile复制进去。  
3.在**600_panda_risc_v/software/test/your_prj_name**下编写若干.c和.h。  
> 软件项目引用了**600_panda_risc_v/software/lib**下的驱动或工具程序，其使用的外设都能在Opensoc仓库里找到。  

## 搭建硬件工程
测评SOC的所有源码都在**600_panda_risc_v/fpga/panda_soc_eva**下，  
请修改**imem_init_file**参数为**boot_rom.txt**所在的路径（在**600_panda_risc_v/fpga**下），注意修改PLL的例化。  
在SOC测评工程中，PLL输出时钟的频率是**50MHz**。  

#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|APB-UART|0x4000_3000 ~ 0x4000_3FFF|4KB|
|PLIC|0xF000_0000 ~ 0xF03F_FFFF|4MB|
|CLINT|0xF400_0000 ~ 0xF7FF_FFFF|64MB|
|调试模块|0xFFFF_F800 ~ 0xFFFF_FBFF|1KB|

#### <center>I/O表</center>
|I/O|说明|
|---|---|
|osc_clk|外部晶振时钟输入|
|ext_resetn|外部复位输入, 低有效|
|tck|JTAG时钟输入, 不用时上拉到高电平|
|trst_n|JTAG复位输入, 不用时上拉到高电平|
|tms|JTAG模式输入, 不用时上拉到高电平|
|tdi|JTAG数据输入, 不用时上拉到高电平|
|tdo|JTAG数据输出|
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
可通过JTAG或UART来进行编程烧录。  

#### UART编程烧录
将boot引脚对应的拨码开关拨到**低电平**，此时CPU运行bootrom程序。  
将编译产生的.bin文件复制到**600_panda_risc_v/scripts**下，然后在scripts文件夹打开命令行终端，输入：  
`` python .\uart_prog.py ``  
然后，按提示打开串口（必须要输入打开的串口名才能打开，如"COM10"），输入.bin文件的路径，等待烧录完成。  
![说明3](../img/panda_risc_v_3.png)  
最后，将boot引脚对应的拨码开关拨到**高电平**，复位CPU，即可见CPU运行烧录的程序。  
> 如果提示无法接收到编程应答，那么可以在打开串口后（输入了要连接的串口后），按一下外部复位引脚。  

#### JTAG下载
连接好DapLink，3v3可以不连，**nRST需要连接**。  
![说明4](../img/panda_risc_v_4.jpg)  
确保您的电脑已经打开了Telnet服务，否则请去控制面板/程序/启动或改变Windows功能下，找到Telnet Client并打开。  
在**600_panda_risc_v/tools/openocd**下打开命令行终端，输入：  
`` .\openocd.exe -f panda_risc_v.cfg ``  
然后，在同一目录再打开另外1个命令行终端，输入：  
`` telnet localhost 4444 ``  
接着，如果该目录下有bin文件，可以在**telnet**命令行终端输入以下命令来下载程序：  
`` load_image tube_scan.bin 0x00000800 ``  
最后，让处理器从0x00000800地址继续运行，在**telnet**命令行终端输入：  
`` resume 0x00000800 ``  

#### JTAG调试
JTAG调试应在完成JTAG下载后再进行。  
GNU工具链（需要自行下载，参见步骤"配置编译环境"）中已经包含了gdb工具，位于600_panda_risc_v/tools/gnu-mcu-eclipse-riscv-none-gcc-8.2.0-2.2-20190521-0004-win64/bin。  
将当前程序的elf文件（如tube_scan.elf，elf文件应当带有调试信息）复制到gdb工具所在目录，打开命令行终端，输入：  
`` .\riscv-none-embed-gdb.exe tube_scan.elf ``  
然后，再输入：  
`` target remote localhost:3333 ``  
此时，可以使用[GDB命令](https://blog.csdn.net/ys1115/article/details/130563975)进行在线调试。  

## 使用Eclipse IDE
1.下载Eclipse（[百度云链接](https://pan.baidu.com/s/1Wq-isumnnuQNxXdvCApr0g?pwd=1234)里的eclipse-embedcpp-2025-03-R-win32-x86_64.zip）  
2.将压缩包里的eclipse文件夹解压到任意目录，eclipse是免安装的，其中的eclipse.exe就是可执行程序，可以将它发送到桌面快捷方式。  
3.安装Eclipse Embedded CDT
打开Eclipse，选择Help菜单栏下的Eclipse Marketplace。  
![说明5](../img/panda_risc_v_5.png)  
搜索eclipse embedded，安装Eclipse Embedded CDT。  
![说明6](../img/panda_risc_v_6.png)  
重新启动Eclipse。  
4.配置risc-v工具链  
打开Eclipse，选择Window菜单栏下的Preferences。  
![说明7](../img/panda_risc_v_7.png)  
配置好Build工具的路径，Build工具就是我们在"配置编译环境"小节所安装的MAKE工具，注意要找到其中的bin目录。  
![说明8](../img/panda_risc_v_8.png)  
配置好Openocd工具的路径，它位于**600_panda_risc_v/tools/openocd**下。  
![说明9](../img/panda_risc_v_9.png)  
配置好GNU的路径，GNU就是我们在"配置编译环境"小节所安装的GNU工具链，注意要找到其中的bin目录。  
请先按照下图选择好Default toolchain，即riscv-none-embed-gcc。  
![说明10](../img/panda_risc_v_10.png)  
重新启动Eclipse。  
5.导入示例工程  
打开Eclipse，选择File菜单栏下的Open Projects from File System，点击Directory按钮，  
选择**600_panda_risc_v/software/eclipse_example**下的示例工程文件夹**breathing_led**，点击Finish按钮。  
6.配置工程  
选中工程，打开工程属性配置界面。  
![说明11](../img/panda_risc_v_11.png)  
配置如下，其中Build后命令为：  
`` riscv-none-embed-objcopy -O binary "${ProjName}.elf" "${ProjName}.bin" ``  
![说明12](../img/panda_risc_v_12.png)  
![说明13](../img/panda_risc_v_13.png)  
![说明14](../img/panda_risc_v_14.png)  
![说明15](../img/panda_risc_v_15.png)  
7.编译工程  
选中工程，点左上角的小锤子。  
8.创建Debug配置  
选中工程，右键，选择Run As下的Run Configurations。  
创建一个GDB OpenOCD Debugging（右键，点击New Configuration）。  
配置如下，修改Config options为**600_panda_risc_v/tools/openocd**下的**panda_risc_v.cfg**。  
GDB启动时命令如下：  
````
set remotetimeout 250
set arch riscv:rv32
````
![说明16](../img/panda_risc_v_16.png)  
配置CPU运行/重新运行时的命令：  
`` set $pc=0x800 ``  
![说明17](../img/panda_risc_v_17.png)  
在连接好Daplink，boot引脚为低电平，CPU复位释放后，点击RUN即开始运行程序。  
此外，可以选择Debug As来进行在线调试。  
