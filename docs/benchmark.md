# shen-joy vs shen-go benchmark

Measured 2026-09-04T20:17:29Z on Apple M4 (darwin/arm64). Revisions: shen-joy 2df1d73e3eb1+dirty, shen-go e36f038b8118. Go toolchain: go version go1.27.0 darwin/arm64. Image checksum: d935564b.

| Runtime | Median ns/op | Min-max ns/op | Samples |
|---|---:|---:|---:|
| shen-joy | 3390431 | 2907425-4263910 | 10 |
| shen-go | 1477264 | 1391606-1619170 | 10 |

On this run, shen-go is 2.30x faster than shen-joy for this kernel. This is one narrow VM comparison, not a claim about full Shen performance.

Raw ns/op samples: shen-joy [3029292, 2907425, 3197170, 3627899, 4263910, 3843251, 3510167, 3339589, 3441274, 3234388]; shen-go [1545652, 1434412, 1391606, 1529065, 1471363, 1483118, 1541881, 1619170, 1471409, 1419468].

## Method

The shared workload is a first-order self-tail-recursive sum from 8000 to zero; both return 32004000. It exercises calls, tail calls, locals, integer equality, addition, subtraction, and branching. shen-joy executes 96012 bytecode instructions per operation.

Parsing, image decoding, Shen kernel boot, and process startup are outside the timed regions. shen-joy loads and validates the image once, warms up, then times repeated calls to the allocation-free VM. shen-go uses its Go benchmark BenchmarkVMSumMid, which defines the KLambda function and parses the call before timing repeated Eval operations. The runtime entry APIs differ slightly, so treat the ratio as directional and reproduce it on the deployment CPU.

Reproduce from the Bifrost checkout:

~~~sh
nix run .#env -- shen-go shen-joy -- go run . bench shen-joy-vs-shen-go --samples 10 --iterations 500 --benchtime 500ms
~~~
