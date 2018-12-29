
;; Structure of the Compiler
(define (compile exp target linkage)
  (cond ((self-evaluating? exp)
	 (compile-self-evaluating exp target linkage))
	((quoted? exp) (compile-quoted exp target linkage))
	((variable? exp)
	 (compile-variable exp target linkage))
	((assignment? exp)
	 (compile-assignment exp target linkage))
	((definition? exp)
	 (compile-definition exp target linkage))
	((if? exp) (compile-if exp target linkage))
	((lambda? exp) (compile-lambda exp target linkage))
	((begin? exp)
	 (compile-sequence (begin-actions exp)
			   target
			   linkage))
	((cond? exp) (compile (cond->if exp) target linkage))
	((application? exp)
	 (compile-application exp target linkage))
	(else
	 (error "Unknown expression type -- COMPILE" exp))))

;; Instructoin sequences and stack usage
(define (make-instruction-sequence needs modifies statements)
  (list needs modifies statements))

(define (empty-instruction-sequence)
  (list '() '() '()))

;; Compiling Expressions
;; Compilink linkage code
(define (compile-linkage linkage)
  (cond ((eq? linkage 'return)
	 (make-instruction-sequence '(continue) '()
				    '((goto (reg continue)))))
	((eq? linkage 'next)
	 (empty-instruction-sequence))
	(else
	 (make-instruction-sequence '() '()
				    `((goto (reg ,linkage)))))))

(define (end-with-linkage linkage instruction-sequence)
  (preserving '(continue) instruction-sequence
	      (compile-linkage linkage)))

;; Compiling simple expressions
(define (compile-self-evaluating exp target linkage)
  (end-with-linkage
   linkage
   (make-instruction-sequence '() (list target)
			      `((assign ,target (const ,exp))))))

(define (compile-quoted exp target linkage)
  (end-with-linkage
   linkage
   (make-instruction-sequence
    '() (list target)
    `((assign ,target (const ,(test-of-quotation exp)))))))

(define (compile-variable exp target linkage)
  (end-with-linkage
   linkage
   (make-instruction-sequence
    '(env) (list target)
    `((assign ,target
	      (op lookup-variable-value)
	      (const ,exp)
	      (reg env))))))

(define (compile-assignment exp target linkage)
  (let ((var (assignment-variable exp))
	(get-value-code
	 (compile (assignment-value exp) 'val 'next)))
    (end-with-linkage
     linkage
     (preserving '(env)
		 get-value-code
		 (make-instruction-sequence
		  '(env val) (list target)
		  '((perform (op set-variable-value!)
			     (const ,var)
			     (reg val)
			     (reg env))
		    (assign ,target (const ok))))))))

(define (compile-definition exp target linkage)
  (let ((var (definition-variable exp))
	(get-value-code
	 (compile (definition-value exp) 'val 'next)))
    (end-with-linkage
     linkage
     (preserving '(env)
		 get-value-code
		 (make-instruction-sequence
		  '(env val) (list target)
		  '((perform (op define-variable!)
			     (const ,var)
			     (reg val)
			     (reg env))
		    (assign ,target (const ok))))))))

;; Compiling conditional expressions
(define (compile-if exp target linkage)
  (let ((t-branch (make-label 'true-branch))
	(f-branch (make-label 'false-branch))
	(after-if (make-label 'after-if)))
    (let ((consequent-linkage
	   (if (eq? linkage 'next) after-if linkage)))
      (let ((p-code (compile (if-predicate exp) 'val 'next))
	    (c-code
	     (compile
	      (if-consequent exp) target consequent-linkage))
	    (a-code
	     (compile (if-alternative exp) target linkage)))
	(preserving '(env continue)
		    p-code
		    (append-instruction-sequences
		     (make-instruction-sequence '(val) '()
						`((test (op false?) (reg val))
						  (branch (label ,f-branch))))
		     (parallel-instruction-sequences
		      (append-instruction-sequences t-branch c-code)
		      (append-instruction-sequences f-branch a-code))
		     after-if))))))

(define label-counter 0)
(define (new-label-number)
  (set! label-counter (+ 1 label-counter))
  label-counter)
(define (make-label name)
  (string->symbol
   (string-append (symbol->string name)
		  (number->string (new-label-number)))))

;; Compiling sequences
(define (compile-sequence seq target linkage)
  (if (last-exp? seq)
      (compile (first-exp seq) target linkage)
      (preserving '(env continue)
		  (compile (first-exp seq) target 'next)
		  (compile-sequence (rest-exps seq) target linkage))))

;; Compiling lambda expressions
(define (compile-lambda exp target linkage)
  (let ((proc-entry (make-label 'entry))
	(after-lambda (make-label 'after-lambda)))
    (let ((lambda-linkage
	   (if (eq? linkage 'next) after-lambda linkage)))
      (append-instruction-sequences
       (tack-on-instruction-sequence
	(end-with-linkage lambda-linkage
			  (make-instruction-sequence '(env) (list target)
						     `((assign ,target
							       (op make-compiled-procedure)
							       (label ,proc-entry)
							       (reg env)))))
	(compile-lambda-body exp proc-entry))
       after-lambda))))

(define (compile-lambda-body exp proc-entry)
  (let ((formals (lambda-parameters exp)))
    (append-instruction-sequences
     (make-instruction-sequence
      '(env proc argl) '(env)
      `(,proc-entry
	(assign env (op compiled-procedure-env) (reg proc))
	(assign env
		(op extend-environment)
		(const ,formals)
		(reg argl)
		(reg env))))
     (compile-sequence (lambda-body exp) 'val 'return))))

;; Compiling Combinations
(define (compile-application exp target linkage)
  (let ((proc-code (compile (operator exp) 'proc 'next))
	(operand-codes
	 (map (lambda (operand) (compile operand 'val 'next))
	      (operands exp))))
    (preserving '(env continue)
		proc-code
		(preserving '(proc continue)
			    (construct-arglist operand-codes)
			    (compile-procedure-call target linkage)))))

(define (construct-arglist operand-codes)
  (let ((operand-codes (reverse operand-codes)))
    (if (null? operand-codes)
	(make-instruction-sequence '() '(argl)
				   '((assign argl (const ()))))
	(let ((code-to-get-last-arg
	       (append-instruction-sequences
		(car operand-codes)
		(make-instruction-sequence '(val) '(argl)
					   '((assign argl (op list) (reg val)))))))
	  (if (null? (cdr operand-codes))
	      code-to-get-last-arg
	      (preserving '(env)
			  code-to-get-last-arg
			  (code-to-get-rest-args (cdr operand-codes))))))))

(define (code-to-get-rest-args operand-codes)
  (let ((code-for-next-arg
	 (preserving '(argl)
		     (car operand-codes)
		     (make-instruction-sequence
		      '(val argl) '(argl)
		      '((assign argl (op cons) (reg val) (reg argl)))))))
    (if (null? (cdr operand-codes))
	code-for-next-arg
	(preserving '(env)
		    code-for-next-arg
		    (code-to-get-rest-args (cdr operand-codes))))))
		     

	
		     
	

(define (make-compiled-procedure entry env)
  (list 'compiled-procedure entry env))
(define (compiled-procedure? proc)
  (tagged-list? proc 'compiled-procedure))
(define (compiled-procedure-entry c-proc) (cadr c-proc))
(define (compiled-procedure-env c-proc) (caddr c-proc))
