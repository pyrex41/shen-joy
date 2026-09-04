#ifndef SHEN_JOY_VM_H
#define SHEN_JOY_VM_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
  SJ_OK = 0, SJ_BAD_IMAGE, SJ_STACK_LIMIT, SJ_RETURN_LIMIT,
  SJ_TYPE_ERROR, SJ_ARITHMETIC_OVERFLOW, SJ_FUEL_EXHAUSTED,
  SJ_HEAP_LIMIT, SJ_MISSING_IMPORT, SJ_UNSUPPORTED, SJ_HEAP_BOUNDS,
  SJ_DEVICE_ERROR
} sj_status;

struct sj_machine;
typedef sj_status (*sj_device_fn)(uint32_t, struct sj_machine *, void *);

typedef struct sj_machine {
  const uint32_t *code;
  size_t code_words;
  const uint32_t *constants;
  size_t constant_words;
  uint32_t *data;
  size_t data_words;
  int32_t *returns;
  size_t return_words;
  uint32_t *heap;
  size_t heap_words;
  size_t sp, rp, hp, fp, pc;
  uint64_t fuel, steps;
  uint8_t entering, tailing;
  sj_device_fn device;
  void *device_context;
} sj_machine;

typedef struct { sj_status status; uint32_t value; size_t pc; uint64_t steps; } sj_result;

sj_result sj_vm_run(sj_machine *machine, size_t entry);

#endif
