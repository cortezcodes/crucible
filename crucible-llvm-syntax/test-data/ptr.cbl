(defun @test-ptr () (Ptr 64)
  (start start:
    (let blk0 (the Nat 0))
    (let off0 (bv 64 0))
    (let p0 (ptr 64 blk0 off0))
    (let p (ptr-ite 64 #t p0 p0))
    (let blk (ptr-block 64 p))
    (let off (ptr-offset 64 p))
    (assert! (equal? blk0 blk) "block numbers equal")
    (assert! (equal? off0 off) "offsets equal")

    (let sz (bv 64 1))
    (let a (alloca none sz))

    (return p)))
