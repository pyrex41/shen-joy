#include "shen_joy_vm.h"
#include <limits.h>

#define OP(i) ((uint8_t)((i) >> 24))
#define ARG(i) ((uint32_t)((i) & 0x00ffffffu))
#define TAG(v) ((v) & 3u)
#define FALSE_VALUE 2u
#define TRUE_VALUE 6u

static int32_t signed_arg(uint32_t i) {
  uint32_t x = ARG(i);
  return (int32_t)(x | ((x & 0x00800000u) ? 0xff000000u : 0u));
}
static int push(sj_machine *m, uint32_t v) {
  if (m->sp >= m->data_words) return 0;
  m->data[m->sp++] = v; return 1;
}
static int pop(sj_machine *m, uint32_t *v) {
  if (!m->sp) return 0;
  *v = m->data[--m->sp]; return 1;
}
static int fixnum(uint32_t v, int32_t *n) {
  if (TAG(v) != 1u) return 0;
  *n = ((int32_t)v) >> 2; return 1;
}
static int make_fixnum(int64_t n, uint32_t *v) {
  if (n < -(INT64_C(1)<<29) || n > (INT64_C(1)<<29)-1) return 0;
  *v = ((uint32_t)(int32_t)n << 2) | 1u; return 1;
}
static int continuation(sj_machine *m, size_t pc) {
  if (m->rp + 3 > m->return_words) return 0;
  m->returns[m->rp++] = (int32_t)pc;
  m->returns[m->rp++] = (int32_t)m->fp;
  m->returns[m->rp++] = 0; return 1;
}
static sj_result done(sj_machine *m, sj_status s) {
  sj_result r = {s, m->sp ? m->data[m->sp-1] : 0, m->pc, m->steps}; return r;
}

sj_result sj_vm_run(sj_machine *m, size_t entry) {
  if (!m || !m->code || entry >= m->code_words || !m->data || !m->returns)
    return (sj_result){SJ_BAD_IMAGE, 0, 0, 0};
  m->sp=m->rp=m->fp=0; m->hp=1; m->pc=entry; m->steps=0; m->entering=m->tailing=0;
  for (;;) {
    if (m->fuel && m->steps >= m->fuel) return done(m, SJ_FUEL_EXHAUSTED);
    if (m->pc >= m->code_words) return done(m, SJ_BAD_IMAGE);
    uint32_t ins=m->code[m->pc], a=ARG(ins), av,bv,v; int32_t a32,b32; size_t next=m->pc+1;
    m->steps++;
    switch (OP(ins)) {
    case 0: return done(m,SJ_OK);
    case 1: if(!make_fixnum(signed_arg(ins),&v)||!push(m,v)) return done(m,SJ_STACK_LIMIT); break;
    case 2: if(!m->sp||!push(m,m->data[m->sp-1])) return done(m,SJ_STACK_LIMIT); break;
    case 3: if(!pop(m,&v)) return done(m,SJ_BAD_IMAGE); break;
    case 4: if(m->sp<2) return done(m,SJ_BAD_IMAGE); v=m->data[m->sp-1];m->data[m->sp-1]=m->data[m->sp-2];m->data[m->sp-2]=v;break;
    case 5: case 6: case 7: case 9:
      if(!pop(m,&bv)||!pop(m,&av))return done(m,SJ_BAD_IMAGE);
      if(!fixnum(av,&a32)||!fixnum(bv,&b32))return done(m,SJ_TYPE_ERROR);
      if(OP(ins)==9)v=a32<b32?TRUE_VALUE:FALSE_VALUE;
      else if(!make_fixnum(OP(ins)==5?(int64_t)a32+b32:OP(ins)==6?(int64_t)a32-b32:(int64_t)a32*b32,&v))return done(m,SJ_ARITHMETIC_OVERFLOW);
      if(!push(m,v))return done(m,SJ_STACK_LIMIT);
      break;
    case 8: if(!pop(m,&bv)||!pop(m,&av))return done(m,SJ_BAD_IMAGE);if(TAG(av)==0||TAG(bv)==0)return done(m,SJ_UNSUPPORTED);if(!push(m,av==bv?TRUE_VALUE:FALSE_VALUE))return done(m,SJ_STACK_LIMIT);break;
    case 10: next=(size_t)((int64_t)next+signed_arg(ins));break;
    case 11: if(!pop(m,&v))return done(m,SJ_BAD_IMAGE);if(v==FALSE_VALUE)next=(size_t)((int64_t)next+signed_arg(ins));else if(v!=TRUE_VALUE)return done(m,SJ_TYPE_ERROR);break;
    case 12: if(!continuation(m,next))return done(m,SJ_RETURN_LIMIT);m->entering=1;next=a;break;
    case 13: m->tailing=1;next=a;break;
    case 14:
      if(m->rp<3)return done(m,SJ_OK);
      {size_t ret=(size_t)m->returns[m->rp-3], oldfp=(size_t)m->returns[m->rp-2]; int cleanup=m->returns[m->rp-1];m->rp-=3;
       if(cleanup){if(!pop(m,&v))return done(m,SJ_BAD_IMAGE);m->sp=m->fp;if(!push(m,v))return done(m,SJ_STACK_LIMIT);}m->fp=oldfp;next=ret;}break;
    case 15: if(a>0x3fffffffu||!push(m,(a<<2)|3u))return done(m,SJ_STACK_LIMIT);break;
    case 16: if(!pop(m,&v)||TAG(v)!=3u)return done(m,SJ_TYPE_ERROR);if(!continuation(m,next))return done(m,SJ_RETURN_LIMIT);next=v>>2;break;
    case 17: {size_t arity=a&0xfffu, extra=(a>>12)&0xfffu;if(arity>m->sp)return done(m,SJ_BAD_IMAGE);
      if(m->tailing){size_t src=m->sp-arity;for(size_t i=0;i<arity;i++)m->data[m->fp+i]=m->data[src+i];m->sp=m->fp+arity;m->tailing=0;}
      else {m->fp=m->sp-arity;if(m->entering){if(m->rp<3)return done(m,SJ_BAD_IMAGE);m->returns[m->rp-1]=1;}}
      m->entering=0;while(extra--)if(!push(m,0))return done(m,SJ_STACK_LIMIT);}break;
    case 18: if(m->fp+a>=m->sp||!push(m,m->data[m->fp+a]))return done(m,SJ_BAD_IMAGE);break;
    case 19: if(!m->device)return done(m,SJ_MISSING_IMPORT);{sj_status s=m->device(a,m,m->device_context);if(s!=SJ_OK)return done(m,s);}break;
    case 20: if(!push(m,TRUE_VALUE))return done(m,SJ_STACK_LIMIT);break;
    case 21: if(!push(m,FALSE_VALUE))return done(m,SJ_STACK_LIMIT);break;
    case 22: if(!push(m,0))return done(m,SJ_STACK_LIMIT);break;
    case 23: if(!pop(m,&bv)||!pop(m,&av))return done(m,SJ_BAD_IMAGE);if(!m->heap||m->hp+3>m->heap_words)return done(m,SJ_HEAP_LIMIT);v=(uint32_t)m->hp<<2;m->heap[m->hp]=1;m->heap[m->hp+1]=av;m->heap[m->hp+2]=bv;m->hp+=3;if(!push(m,v))return done(m,SJ_STACK_LIMIT);break;
    case 24: case 25: if(!pop(m,&v)||!v||TAG(v)||((v>>2)+2)>=m->hp||m->heap[v>>2]!=1)return done(m,SJ_HEAP_BOUNDS);if(!push(m,m->heap[(v>>2)+(OP(ins)==24?1:2)]))return done(m,SJ_STACK_LIMIT);break;
    case 26: if(!pop(m,&v)||!push(m,v==0?TRUE_VALUE:FALSE_VALUE))return done(m,SJ_STACK_LIMIT);break;
    case 27: if(!m->heap||m->hp+1+a>m->heap_words)return done(m,SJ_HEAP_LIMIT);v=(uint32_t)m->hp<<2;m->heap[m->hp]=(a<<8)|2;for(uint32_t i=0;i<a;i++)m->heap[m->hp+1+i]=0;m->hp+=1+a;if(!push(m,v))return done(m,SJ_STACK_LIMIT);break;
    case 28: if(!pop(m,&bv)||!pop(m,&av)||!fixnum(bv,&b32)||!av||TAG(av)||(av>>2)>=m->hp||(m->heap[av>>2]&255)!=2)return done(m,SJ_TYPE_ERROR);a=m->heap[av>>2]>>8;if(b32<0||(uint32_t)b32>=a)return done(m,SJ_HEAP_BOUNDS);if(!push(m,m->heap[(av>>2)+1+(uint32_t)b32]))return done(m,SJ_STACK_LIMIT);break;
    case 29: if(!pop(m,&v)||!pop(m,&bv)||!pop(m,&av)||!fixnum(bv,&b32)||!av||TAG(av)||(av>>2)>=m->hp||(m->heap[av>>2]&255)!=2)return done(m,SJ_TYPE_ERROR);a=m->heap[av>>2]>>8;if(b32<0||(uint32_t)b32>=a)return done(m,SJ_HEAP_BOUNDS);m->heap[(av>>2)+1+(uint32_t)b32]=v;if(!push(m,av))return done(m,SJ_STACK_LIMIT);break;
    case 30: if(a>=m->constant_words||!push(m,m->constants[a]))return done(m,SJ_BAD_IMAGE);break;
    case 31: if(!pop(m,&v)||m->fp+a>=m->sp)return done(m,SJ_BAD_IMAGE);m->data[m->fp+a]=v;break;
    case 32: if(!m->sp||!fixnum(m->data[m->sp-1],&a32))return done(m,SJ_TYPE_ERROR);if(!make_fixnum((int64_t)a32*a32,&v))return done(m,SJ_ARITHMETIC_OVERFLOW);m->data[m->sp-1]=v;break;
    default:return done(m,SJ_BAD_IMAGE);
    }
    m->pc=next;
  }
}
