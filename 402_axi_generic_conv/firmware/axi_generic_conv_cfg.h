#define RD_REQ_BUF_ALIGNMENT 64 // 读请求描述子缓存区首地址对齐到的字节数
#define WT_REQ_BUF_ALIGNMENT 64 // 写请求描述子缓存区首地址对齐到的字节数

#define MAX_RD_REQ_N 1024 * 1024 * 16 // 最大的读请求个数
#define MAX_WT_REQ_N 65536 // 最大的写请求个数
