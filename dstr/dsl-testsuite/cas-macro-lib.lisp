(defun preserve-clauses (&rest vars)
  (mapcar (lambda (var)
            `(= ,(next-var-symbol var) ,var))
          vars))

(defmacro preserve (&rest vars)
  (apply #'preserve-clauses vars))
