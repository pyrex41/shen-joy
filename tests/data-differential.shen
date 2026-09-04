(let V (absvector 4)
  (do
    (address-> V 2 42)
    (output "SJ_RESULT=~A~%" (+ (hd (tl [1 9])) (<-address V 2)))))
