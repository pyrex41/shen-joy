(define square+1
  X -> (+ (* X X) 1))

(define sum-loop
  0 Acc -> Acc
  N Acc -> (sum-loop (- N 1) (+ Acc N)))

(output "SJ_RESULT=~A~%" (+ (sum-loop 10 0) (square+1 6)))
