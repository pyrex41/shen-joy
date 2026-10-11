#include "shen_joy_vm.h"
#include <stdio.h>

int main(int argc, char **argv) {
  uint32_t code[256], data[64], heap[1]; int32_t returns[24]; size_t n=0;
  const char *path=argc>1?argv[1]:"conformance/core.hex";
  FILE *f=fopen(path,"r"); if(!f)return 2;
  while(n<256 && fscanf(f,"%x",&code[n])==1)n++;
  fclose(f);
  sj_machine m={.code=code,.code_words=n,.data=data,.data_words=64,.returns=returns,.return_words=24,.heap=heap,.heap_words=1,.fuel=100};
  sj_result r=sj_vm_run(&m,0); int32_t value=((int32_t)r.value)>>2;
  printf("RESULT=%d STATUS=%d STEPS=%llu\n",value,(int)r.status,(unsigned long long)r.steps);
  return 0;
}
