import os
import argparse
import subprocess

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir_name", type=str, default="file", help="isa dir to test")
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

if __name__ == "__main__":
    opt = parse_opt()
    
    dir_name = opt.dir_name
    
    TxtFileList = GetFileFromThisRootDirV2(dir_name, "txt")
    
    file_res = open("isa_test_res.txt", 'w')
    pass_flag = True
    
    for f in TxtFileList:
        print(f)
        file_res.writelines(f + "\n")
        
        file_do = open("modelsim_simulate.do", 'w')
        file_do.writelines("vsim -voptargs=+acc xil_defaultlib.tb_panda_risc_v -g IMEM_INIT_FILE=\""+f.replace("\\", "/")+"\" -g DMEM_INIT_FILE=\""+f.replace("\\", "/")+"\"\n")
        file_do.writelines("set NumericStdNoWarnings 1\n")
        file_do.writelines("set StdArithNoWarnings 1\n")
        file_do.writelines("run 40us\n")
        file_do.writelines("quit\n")
        file_do.close()
        
        subprocess.run("make", shell=True)
        
        file_log = open("simulate.log", 'r')
        log_content = file_log.read()
        
        if "~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~" in log_content:
            print("pass")
            file_res.writelines("pass\n")
        else:
            print("fail XXXXXXXXXXXXXXXXXXXX")
            file_res.writelines("fail XXXXXXXXXXXXXXXXXXXX\n")
            pass_flag = False
        
        file_log.close()
        
        subprocess.run("make clean", shell=True)
        
        print()
        file_res.writelines("\n")
    
    if pass_flag:
        file_res.writelines("All passed!\n")
    else:
        file_res.writelines("Some failed!\n")
    
    file_res.close()
