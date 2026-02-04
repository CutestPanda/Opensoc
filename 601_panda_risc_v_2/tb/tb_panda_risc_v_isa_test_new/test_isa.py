import os
import argparse
import subprocess

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir_name", type=str, default="test_compiled", help="isa dir to test")
    parser.add_argument("--run_time", type=str, default="100us", help="time for simulation")
    opt = parser.parse_args()
    
    return opt
    
def GetFileFromThisRootDirV2(target_dir, target_suffix="pxy"):
    find_res = []
    target_suffix_dot = "." + target_suffix
    walk_generator = os.walk(target_dir)
    for root_path, dirs, files in walk_generator:
        if len(files) < 1:
            continue
        for file in files:
            file_name, suffix_name = os.path.splitext(file)
            if suffix_name == target_suffix_dot:
                find_res.append(os.path.abspath(os.path.join(root_path, file)))
    return find_res

def remove_temp_file():
    subprocess.run("rm .\modelsim.ini", shell=True)
    subprocess.run("rm -r .\modelsim_lib", shell=True)

if __name__ == "__main__":
    opt = parse_opt()
    
    dir_name = opt.dir_name
    run_time = opt.run_time
    
    TxtFileList = GetFileFromThisRootDirV2(dir_name, "mem")
    
    file_res = open("isa_test_res.txt", 'w')
    pass_flag = True
    
    subprocess.run("make comp", shell=True)
    
    file_log = open("compile.log", 'r')
    log_content = file_log.read()
    
    if not ("Errors: 0" in log_content):
        print("fail to compile!")
        
        remove_temp_file()
        file_log.close()
        
        exit()
    
    file_log.close()
    
    for f in TxtFileList:
        print(f)
        file_res.writelines(f + "\n")
        
        file_do = open("modelsim_simulate.do", 'w')
        file_do.writelines("vsim -voptargs=+acc xil_defaultlib.tb_isa_test -g IMEM_INIT_FILE=\""+f.replace("\\", "/")+"\" -g DMEM_INIT_FILE=\""+f.replace("\\", "/")+"\"\n")
        file_do.writelines("set NumericStdNoWarnings 1\n")
        file_do.writelines("set StdArithNoWarnings 1\n")
        file_do.writelines("run " + run_time + "\n")
        file_do.writelines("quit\n")
        file_do.close()
        
        subprocess.run("make sim", shell=True)
        
        file_log = open("simulate.log", 'r')
        log_content = file_log.read()
        
        minstret = 0
        mcycle = 0
        
        for line in log_content.split('\n'):
            if "minstret" in line:
                minstret = int(line.split('=')[1])
            elif "mcycle" in line:
                mcycle = int(line.split('=')[1])
        
        if mcycle != 0:
            ipc = str(minstret / mcycle)
        else:
            ipc = "NAN"
        
        if "~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~" in log_content:
            print("pass")
            file_res.writelines("pass\n")
        else:
            print("fail XXXXXXXXXXXXXXXXXXXX")
            file_res.writelines("fail XXXXXXXXXXXXXXXXXXXX\n")
            pass_flag = False
        
        file_res.writelines("ipc = " + ipc + "\n")
        
        file_log.close()
        
        subprocess.run("make clean", shell=True)
        
        print()
        file_res.writelines("\n")
    
    if pass_flag:
        file_res.writelines("All passed!\n")
    else:
        file_res.writelines("Some failed!\n")
    
    file_res.close()
    remove_temp_file()
