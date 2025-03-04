## 小胖达处理器核仿真说明

#### 安装make
参见小胖达risc-v首页README的**配置编译环境**小节。  

#### 指定modelsim安装路径
修改Makefile中的**MODELSIM_PATH**变量, 其值为modelsim安装路径。  

#### 放置待测模块
将**600_panda_risc_v/rtl**下的所有.v文件复制到**to_compile/dut**下。  

#### 测试所有指令
测试前确保已经安装了python。  
在命令行终端输入来开始测试：  
`` python .\test_isa.py --dir_name inst_test ``  
测试结果保存在**isa_test_res.txt**里。  
