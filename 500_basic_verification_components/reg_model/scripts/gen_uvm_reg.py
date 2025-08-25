import os
import re
import argparse

class RegFieldDef:
    def __init__(self, name="field", f_len="8", lsb_pos="0", access="RW", volatile="1", rst_v="0", has_rst="1", \
        is_rand="1", indvd_acsb="0"):
        self.__name = name
        self.__f_len = f_len
        self.__lsb_pos = lsb_pos
        self.__access = '\"' + access + '\"'
        self.__volatile = volatile
        self.__rst_v = rst_v
        self.__has_rst = has_rst
        self.__is_rand = is_rand
        self.__indvd_acsb = indvd_acsb
    
    def get_member_def_code(self, tab_str="    "):
        return tab_str + ("rand " if (self.__is_rand == "1") else "") + "uvm_reg_field " + self.__name + ";\n"
    
    def get_init_code(self, tab_str="        "):
        return tab_str + "this." + self.__name + " = uvm_reg_field::type_id::create(\"" + self.__name + "\");\n" + \
            tab_str + "this." + self.__name + ".configure(this, " + self.__f_len + ", " + self.__lsb_pos + ", " + \
            self.__access + ", " + self.__volatile + ", " + self.__rst_v + ", " + self.__has_rst + ", " + self.__is_rand + \
            ", " + self.__indvd_acsb + ");\n"

class RegDef:
    def __init__(self, name="Reg", n_bits=32, coverage_mode="UVM_NO_COVERAGE"):
        self.__name = name
        self.__n_bits = n_bits
        self.__coverage_mode = coverage_mode
        
        self.__class_title_str = ""
        self.__member_def_str = ""
        self.__registry_str = ""
        self.__constructor_str = ""
        self.__build_func_str = ""
        self.__class_foot_str = ""
        
        self.__field_arr = []
    
    def add_reg_field(self, reg_field=None):
        if reg_field != None:
            self.__field_arr.append(reg_field)
    
    def gen_code(self):
        self.__class_title_str = "class " + self.__name + " extends uvm_reg;\n\n"
        
        self.__member_def_str = ""
        for reg_field in self.__field_arr:
            self.__member_def_str += reg_field.get_member_def_code(self.__insert_tab(1))
        self.__member_def_str += "\n"
        
        self.__registry_str = self.__insert_tab(1) + "`uvm_object_utils(" + self.__name + ")\n\n"
        
        self.__constructor_str = self.__insert_tab(1) + "function new(input string name = \"" + self.__name + "\");\n"
        self.__constructor_str += self.__insert_tab(2) + "super.new(name, " + str(self.__n_bits) + \
            ", " + self.__coverage_mode + ");\n"
        self.__constructor_str += self.__insert_tab(1) + "endfunction\n\n"
        
        self.__build_func_str = self.__insert_tab(1) + "virtual function void build();\n"
        for i in range(0, len(self.__field_arr)):
            self.__build_func_str += self.__field_arr[i].get_init_code(self.__insert_tab(2))
            
            if i != (len(self.__field_arr)-1):
                self.__build_func_str += "\n"
        self.__build_func_str += self.__insert_tab(1) + "endfunction\n\n"
        
        self.__class_foot_str = "endclass\n"
        
        return self.__class_title_str + self.__member_def_str + self.__registry_str + self.__constructor_str + \
            self.__build_func_str + self.__class_foot_str
    
    def __insert_tab(self, n):
        return "".join(["    " for _ in range(n)])

def parse_reg_define_str(lines):
    lines = list(filter(lambda l: re.sub(r"[\s\n]+", "", l) != "", lines))
    
    reg_property_arr = []
    for reg_property in lines[0].split(','):
        reg_property = re.sub(r"[\s\n]+", "", reg_property)
        reg_property_arr.append(reg_property.split('=')[1])
    
    reg_obj = RegDef(reg_property_arr[0], int(reg_property_arr[1]), reg_property_arr[2])
    
    for i in range(3, len(lines)):
        field_property = list(filter(lambda p: re.sub(r"[\s\n]+", "", p) != "", lines[i].split("|")))
        field_property = [re.sub(r"\s+", "", s) for s in field_property]
        
        field_obj = RegFieldDef(field_property[0], field_property[1], field_property[2], field_property[3], \
            field_property[4], field_property[5], field_property[6], field_property[7], field_property[8])
        
        reg_obj.add_reg_field(field_obj)
    
    return reg_obj.gen_code()

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", type=str, default="regs.txt", help="File of Reg Description")
    parser.add_argument("-o", type=str, default="code.sv", help="Output SV Code")
    opt = parser.parse_args()
    
    return opt

if __name__ == "__main__":
    opt = parse_opt()
    
    ifile = opt.i
    ofile = opt.o
    
    code_str = ""
    
    with open(ifile, 'r', encoding='utf-8') as fr:
        lines = fr.readlines()
        
        reg_def_title_id = []
        
        for i in range(0, len(lines)):
            if re.match(r"RegName\s*=", lines[i]):
                reg_def_title_id.append(i)
        
        for i in range(0, len(reg_def_title_id)):
            lines_sel = lines[reg_def_title_id[i]:\
                (len(lines) if (i == len(reg_def_title_id)-1) else reg_def_title_id[i+1])]
            code_str += parse_reg_define_str(lines_sel)
            if i != len(reg_def_title_id)-1:
                code_str += "\n"
    
    with open(ofile, 'w', encoding='utf-8') as fr:
        fr.write(code_str)
