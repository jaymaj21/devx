;;;; dstr-dsl-compiler.lisp

(require :asdf)

(defpackage #:dstr-dsl
  (:use #:cl))

(in-package #:dstr-dsl)

(defstruct ir-named
  name
  body)

(defstruct ir-spec
  name
  variables
  domains
  init
  actions
  next
  invariants
  properties)

(defparameter *java-enums* (make-hash-table :test #'equal))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun next-var-symbol (symbol)
    (unless (symbolp symbol)
      (error "Expected symbol for next-state suffixing, got ~S" symbol))
    (intern (concatenate 'string (symbol-name symbol) "+")
            (or (symbol-package symbol) *package*))))

(defmacro same (var)
  `(= ,(next-var-symbol var) ,var))

(defmacro unchanged (&rest vars)
  (mapcar (lambda (var)
            `(= ,(next-var-symbol var) ,var))
          vars))

(defun wildcard-match-p (pattern text)
  (labels ((match-at (pattern-index text-index)
             (cond
               ((= pattern-index (length pattern))
                (= text-index (length text)))
               ((char= (char pattern pattern-index) #\*)
                (or (match-at (1+ pattern-index) text-index)
                    (and (< text-index (length text))
                         (match-at pattern-index (1+ text-index)))))
               ((char= (char pattern pattern-index) #\?)
                (and (< text-index (length text))
                     (match-at (1+ pattern-index) (1+ text-index))))
               (t
                (and (< text-index (length text))
                     (char-equal (char pattern pattern-index) (char text text-index))
                     (match-at (1+ pattern-index) (1+ text-index)))))))
    (match-at 0 0)))

(defun main ()
  (handler-case
      (let ((args (cdr sb-ext:*posix-argv*)))
        (cond
          ((or (null args) (member "--help" args :test #'string=) (member "-h" args :test #'string=))
           (print-usage)
           (sb-ext:exit :code (if args 0 1)))
          ((= (length args) 1)
           (compile-input-path (first args) nil))
          ((= (length args) 2)
           (compile-input-path (first args) (second args)))
          (t
           (error "Expected one input path and an optional output path."))))
    (error (condition)
      (format *error-output* "Error: ~A~%" condition)
      (sb-ext:exit :code 1))))

(defun print-usage ()
  (format *error-output*
          "Usage: sbcl --script scripts/dstr-dsl-compiler.lisp <input.dstr|directory> [output.json|directory]~%"))

(defun compile-input-path (input output)
  (let ((input-path (truename input)))
    (cond
      ((uiop:directory-pathname-p input-path)
       (compile-directory input-path output))
      ((string-equal (pathname-type input-path) "dstr")
       (compile-one-file input-path output))
      (t
       (error "Input must be a .dstr file or a directory, got ~A" input-path)))))

(defun compile-directory (input-dir output-dir)
  (let* ((target-dir (if output-dir
                         (ensure-directory-pathname output-dir)
                         input-dir))
         (files (directory (merge-pathnames "*.dstr" (ensure-directory-pathname input-dir)))))
    (unless files
      (error "No .dstr files found under ~A" input-dir))
    (ensure-directories-exist (merge-pathnames "dummy" target-dir))
    (dolist (file files)
      (let* ((output-file (merge-pathnames
                           (make-pathname :name (pathname-name file) :type "json")
                           target-dir)))
        (compile-one-file file output-file)))))

(defun compile-one-file (input-file output)
  (let ((*java-enums* (make-hash-table :test #'equal)))
    (let* ((output-file (if output
                            (pathname output)
                            (make-pathname :defaults input-file :type "json")))
           (form (load-top-level-forms input-file))
           (ir (parse-system-form form))
           (json-tree (spec-ir->json ir)))
    (ensure-directories-exist output-file)
    (with-open-file (stream output-file
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-json json-tree stream 0)
      (terpri stream))
      (format t "Wrote ~A~%" output-file))))

(defun read-all-forms (path)
  (with-open-file (stream path :direction :input)
    (let ((*read-eval* nil))
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            collect form))))

(defun load-top-level-forms (path)
  (let ((forms (read-all-forms path))
        (system-form nil)
        (base-dir (uiop:pathname-directory-pathname (truename path))))
    (unless forms
      (error "File ~A is empty" path))
    (dolist (form forms)
      (setf system-form (process-top-level-form form path base-dir system-form)))
    (unless system-form
      (error "File ~A must contain a top-level SYSTEM form" path))
    (expand-special-forms system-form)))

(defun process-top-level-form (form source-path base-dir system-form)
  (cond
    ((and (consp form) (symbol-name= (car form) "defmacro"))
     (eval form)
     system-form)
    ((and (consp form) (symbol-name= (car form) "defun"))
     (eval form)
     system-form)
    ((and (consp form) (symbol-name= (car form) "load"))
     (eval-load-form form source-path base-dir)
     system-form)
    ((and (consp form) (symbol-name= (car form) "load-java-enums"))
     (eval-load-java-enums-form form source-path base-dir)
     system-form)
    ((and (consp form) (symbol-name= (car form) "load-proto-enums"))
     (eval-load-proto-enums-form form source-path base-dir)
     system-form)
    ((and (consp form) (symbol-name= (car form) "system"))
     (when system-form
       (error "File ~A must contain exactly one top-level SYSTEM form" source-path))
     form)
    (t
     (error "Unsupported top-level form in ~A: ~S" source-path form))))

(defun eval-load-java-enums-form (form source-path base-dir)
  (unless (> (length form) 1)
    (error "LOAD-JAVA-ENUMS in ~A expects at least one file or directory, got ~S" source-path form))
  (dolist (designator (rest form))
    (load-java-enums-from-path (load-target-pathname designator base-dir))))

(defun eval-load-proto-enums-form (form source-path base-dir)
  (unless (> (length form) 1)
    (error "LOAD-PROTO-ENUMS in ~A expects at least one file or directory, got ~S" source-path form))
  (dolist (designator (rest form))
    (load-proto-enums-from-path (load-target-pathname designator base-dir))))

(defun load-java-enums-from-path (path)
  (load-enums-from-path path "java" #'load-java-enums-from-file "Java enum path not found"))

(defun load-proto-enums-from-path (path)
  (load-enums-from-path path "proto" #'load-proto-enums-from-file "Proto enum path not found"))

(defun load-enums-from-path (path extension loader not-found-message)
  (let ((directory (or (uiop:directory-exists-p path)
                       (uiop:directory-exists-p
                        (uiop:ensure-directory-pathname path)))))
    (cond
      (directory
       (dolist (file (recursive-files-with-extension (uiop:ensure-directory-pathname directory) extension))
         (funcall loader file)))
      ((probe-file path)
       (funcall loader path))
      (t
       (error "~A: ~A" not-found-message path)))))

(defun recursive-files-with-extension (directory extension)
  (append
   (remove-if-not (lambda (file)
                    (string-equal (pathname-type file) extension))
                  (uiop:directory-files directory))
   (mapcan (lambda (subdirectory)
             (recursive-files-with-extension subdirectory extension))
           (uiop:subdirectories directory))))

(defun load-java-enums-from-file (path)
  (when (string-equal (pathname-type path) "java")
    (let ((content (strip-java-comments (read-file-string path))))
      (dolist (entry (parse-java-enums content path))
        (setf (gethash (car entry) *java-enums*) (cdr entry))))))

(defun load-proto-enums-from-file (path)
  (when (string-equal (pathname-type path) "proto")
    (let ((content (strip-java-comments (read-file-string path))))
      (dolist (entry (parse-proto-enums content path))
        (setf (gethash (car entry) *java-enums*) (cdr entry))))))

(defun read-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun strip-java-comments (text)
  (with-output-to-string (out)
    (loop with i = 0
          while (< i (length text))
          do (cond
               ((and (< (1+ i) (length text))
                     (char= (char text i) #\/)
                     (char= (char text (1+ i)) #\/))
                (incf i 2)
                (loop while (and (< i (length text))
                                 (not (member (char text i) '(#\Newline #\Return))))
                      do (incf i)))
               ((and (< (1+ i) (length text))
                     (char= (char text i) #\/)
                     (char= (char text (1+ i)) #\*))
                (incf i 2)
                (loop while (and (< (1+ i) (length text))
                                 (not (and (char= (char text i) #\*)
                                           (char= (char text (1+ i)) #\/))))
                      do (incf i))
                (incf i 2))
               (t
                (write-char (char text i) out)
                (incf i))))))

(defun parse-java-enums (text path)
  (declare (ignore path))
  (let ((entries nil)
        (start 0))
    (loop for enum-pos = (search "enum" text :start2 start :test #'char-equal)
          while enum-pos
          do (if (java-enum-keyword-at-p text enum-pos)
                 (let* ((name-start (skip-java-whitespace text (+ enum-pos 4)))
                        (name-end (scan-java-identifier-end text name-start))
                        (enum-name (and name-end (subseq text name-start name-end)))
                        (brace-pos (and enum-name (position #\{ text :start name-end)))
                        (brace-end (and brace-pos (find-matching-brace text brace-pos))))
                   (when (and enum-name brace-pos brace-end)
                     (push (cons (string-downcase enum-name)
                                 (mapcar #'string-downcase
                                         (parse-java-enum-constants
                                          (subseq text (1+ brace-pos) brace-end))))
                           entries)
                     (setf start (1+ brace-end)))
                   (unless (and enum-name brace-pos brace-end)
                     (setf start (+ enum-pos 4))))
                 (setf start (+ enum-pos 4))))
    (nreverse entries)))

(defun java-enum-keyword-at-p (text index)
  (let ((before (and (> index 0) (char text (1- index))))
        (after-index (+ index 4)))
    (and (or (null before) (not (java-identifier-char-p before)))
         (< after-index (length text))
         (member (char text after-index)
                 '(#\Space #\Tab #\Return #\Newline)))))

(defun skip-java-whitespace (text index)
  (loop while (and (< index (length text))
                   (member (char text index)
                           '(#\Space #\Tab #\Return #\Newline)))
        do (incf index))
  index)

(defun java-identifier-char-p (ch)
  (or (alphanumericp ch) (member ch '(#\_ #\$))))

(defun scan-java-identifier-end (text start)
  (when (and (< start (length text))
             (or (alpha-char-p (char text start))
                 (member (char text start) '(#\_ #\$))))
    (loop with i = (1+ start)
          while (and (< i (length text))
                     (java-identifier-char-p (char text i)))
          do (incf i)
          finally (return i))))

(defun find-matching-brace (text open-index)
  (loop with depth = 0
        for i from open-index below (length text)
        for ch = (char text i)
        do (cond
             ((char= ch #\{) (incf depth))
             ((char= ch #\})
              (decf depth)
              (when (zerop depth)
                (return i))))))

(defun parse-java-enum-constants (body)
  (let* ((constant-region (subseq body 0 (or (position #\; body) (length body))))
         (tokens nil))
    (dolist (part (split-string-on-char constant-region #\,))
      (let* ((trimmed (string-trim '(#\Space #\Tab #\Return #\Newline) part))
             (end (scan-java-identifier-end trimmed 0)))
        (when end
          (push (subseq trimmed 0 end) tokens))))
    (nreverse tokens)))

(defun parse-proto-enums (text path)
  (declare (ignore path))
  (let ((entries nil)
        (start 0))
    (loop for enum-pos = (search "enum" text :start2 start :test #'char-equal)
          while enum-pos
          do (if (java-enum-keyword-at-p text enum-pos)
                 (let* ((name-start (skip-java-whitespace text (+ enum-pos 4)))
                        (name-end (scan-java-identifier-end text name-start))
                        (enum-name (and name-end (subseq text name-start name-end)))
                        (brace-pos (and enum-name (position #\{ text :start name-end)))
                        (brace-end (and brace-pos (find-matching-brace text brace-pos))))
                   (when (and enum-name brace-pos brace-end)
                     (push (cons (string-downcase enum-name)
                                 (mapcar #'string-downcase
                                         (parse-proto-enum-constants
                                          (subseq text (1+ brace-pos) brace-end))))
                           entries)
                     (setf start (1+ brace-end)))
                   (unless (and enum-name brace-pos brace-end)
                     (setf start (+ enum-pos 4))))
                 (setf start (+ enum-pos 4))))
    (nreverse entries)))

(defun parse-proto-enum-constants (body)
  (let ((tokens nil))
    (dolist (statement (split-string-on-char body #\;))
      (let* ((trimmed (string-trim '(#\Space #\Tab #\Return #\Newline) statement))
             (end (scan-java-identifier-end trimmed 0))
             (eq-pos (and end (position #\= trimmed :start end))))
        (when (and end
                   (not (member (string-downcase (subseq trimmed 0 end))
                                '("option" "reserved")
                                :test #'string=))
                   eq-pos
                   (= (skip-java-whitespace trimmed end) eq-pos))
          (push (subseq trimmed 0 end) tokens))))
    (nreverse tokens)))

(defun split-string-on-char (text delimiter)
  (let ((parts nil)
        (start 0))
    (loop for pos = (position delimiter text :start start)
          do (if pos
                 (progn
                   (push (subseq text start pos) parts)
                   (setf start (1+ pos)))
                 (progn
                   (push (subseq text start) parts)
                   (return (nreverse parts)))))))

(defun eval-load-form (form source-path base-dir)
  (unless (= (length form) 2)
    (error "LOAD in ~A expects exactly one argument, got ~S" source-path form))
  (let ((target (load-target-pathname (second form) base-dir)))
    (load target :verbose nil :print nil)))

(defun load-target-pathname (designator base-dir)
  (let* ((raw (etypecase designator
                (string designator)
                (pathname (namestring designator))))
         (candidate (pathname raw)))
    (if (uiop:absolute-pathname-p candidate)
        candidate
        (merge-pathnames candidate base-dir))))

(defun expand-special-forms (form)
  (cond
    ((atom form) form)
    ((symbol-name= (car form) "quote") form)
    ((symbol-name= (car form) "expand")
     (expand-expand-form form))
    ((percent-macro-head-p (car form))
     (expand-percent-macro-form form))
    ((bang-macro-head-p (car form))
     (error "Splicing macro shorthand !... must appear as a list element, got ~S" form))
    ((dsl-macro-call-p form)
     (expand-user-macro-form form))
    (t
     (cons (expand-special-forms (car form))
           (expand-special-forms-list (cdr form))))))

(defun expand-special-forms-list (forms)
  (loop for form in forms
        append (if (and (consp form) (bang-macro-head-p (car form)))
                   (expand-bang-macro-form form)
                   (list (expand-special-forms form)))))

(defun expand-expand-form (form)
  (unless (>= (length form) 2)
    (error "EXPAND requires a macro name, got ~S" form))
  (let ((macro-name (second form)))
    (unless (symbolp macro-name)
      (error "EXPAND macro name must be a symbol, got ~S" macro-name))
    (unless (macro-function macro-name)
      (error "EXPAND references undefined macro ~S" macro-name))
    (expand-special-forms (macroexpand-1 (cons macro-name (cddr form))))))

(defun expand-user-macro-form (form)
  (expand-special-forms (macroexpand-1 form)))

(defun expand-percent-macro-form (form)
  (let* ((head (car form))
         (name (symbol-name head)))
    (unless (> (length name) 1)
      (error "Percent macro shorthand requires a name after %, got ~S" form))
    (expand-expand-form
     (cons 'expand
           (cons (intern (subseq name 1) (or (symbol-package head) *package*))
                 (cdr form))))))

(defun expand-bang-macro-form (form)
  (let* ((head (car form))
         (name (symbol-name head)))
    (unless (> (length name) 1)
      (error "Splicing macro shorthand requires a name after !, got ~S" form))
    (let ((expanded (macroexpand-1
                     (cons (intern (subseq name 1) (or (symbol-package head) *package*))
                           (cdr form)))))
      (unless (listp expanded)
        (error "Splicing macro !~A must expand to a list, got ~S" (subseq name 1) expanded))
      (expand-special-forms-list expanded))))

(defun parse-system-form (form)
  (unless (and (consp form) (symbol-name= (car form) "system"))
    (error "Top-level form must be (system ...), got ~S" form))
  (destructuring-bind (_system raw-name &rest clauses) form
    (declare (ignore _system))
    (let ((name (dsl-name raw-name))
          (variables nil)
          (domains (make-hash-table :test #'equal))
          (actions nil)
          (invariants nil)
          (properties nil)
          (init nil)
          (next nil))
      (dolist (clause clauses)
        (unless (consp clause)
          (error "System clause must be a list, got ~S" clause))
        (let ((head (car clause))
              (tail (cdr clause)))
          (cond
            ((symbol-name= head "vars")
             (when variables
               (error "Only one VARS clause is allowed"))
             (setf variables (parse-vars tail)))
            ((symbol-name= head "vars*")
             (when variables
               (error "Only one VARS clause is allowed"))
             (setf variables (parse-vars-product tail)))
            ((symbol-name= head "domain")
             (destructuring-bind (var &rest domain-body) tail
               (setf (gethash (dsl-name var) domains)
                     (parse-domain-clause var domain-body))))
            ((symbol-name= head "domain*")
             (dolist (entry (parse-domain-star-clause tail variables domains))
               (setf (gethash (car entry) domains) (cdr entry))))
            ((symbol-name= head "init")
             (when init
               (error "Only one INIT clause is allowed"))
             (setf init tail))
            ((symbol-name= head "next")
             (when next
               (error "Only one NEXT clause is allowed"))
             (setf next tail))
            ((symbol-name= head "action")
             (push (parse-named-clause "action" tail) actions))
            ((symbol-name= head "invariant")
             (push (parse-named-clause "invariant" tail) invariants))
            ((symbol-name= head "property")
             (push (parse-named-clause "property" tail) properties))
            (t
             (error "Unknown system clause ~S" head)))))
      (unless variables
        (error "SYSTEM requires a VARS clause"))
      (unless init
        (error "SYSTEM requires an INIT clause"))
      (unless next
        (error "SYSTEM requires a NEXT clause"))
      (validate-domain-coverage variables domains)
      (let* ((ordered-actions (nreverse actions))
             (ordered-invariants (nreverse invariants))
             (ordered-properties (nreverse properties))
             (action-names (mapcar #'ir-named-name ordered-actions))
             (context (make-context variables action-names)))
        (make-ir-spec
         :name name
         :variables variables
         :domains (loop for variable in variables
                        collect (cons variable (gethash variable domains)))
         :init (compile-body init context nil nil)
         :actions (mapcar (lambda (action)
                            (make-ir-named
                             :name (ir-named-name action)
                             :body (compile-body (ir-named-body action) context t nil)))
                          ordered-actions)
         :next (compile-body next context t t)
         :invariants (mapcar (lambda (inv)
                               (make-ir-named
                                :name (ir-named-name inv)
                                :body (compile-body (ir-named-body inv) context nil nil)))
                             ordered-invariants)
         :properties (mapcar (lambda (prop)
                               (make-ir-named
                                :name (ir-named-name prop)
                                :body (compile-body (ir-named-body prop) context nil nil)))
                             ordered-properties))))))

(defun parse-vars (vars)
  (unless vars
    (error "VARS requires at least one variable"))
  (let ((names (mapcar #'dsl-name vars)))
    (when (/= (length names) (length (remove-duplicates names :test #'equal)))
      (error "Duplicate variable name in VARS clause: ~S" vars))
    names))

(defun parse-vars-product (tail)
  (unless (= (length tail) 4)
    (error "VARS* expects: (vars* separator (group1 ...) * (group2 ...)), got ~S" tail))
  (destructuring-bind (separator left-group marker right-group) tail
    (unless (string= (dsl-name marker) "*")
      (error "VARS* expects * as the third argument, got ~S" marker))
    (unless (listp left-group)
      (error "VARS* left group must be a list, got ~S" left-group))
    (unless (listp right-group)
      (error "VARS* right group must be a list, got ~S" right-group))
    (unless left-group
      (error "VARS* left group cannot be empty"))
    (unless right-group
      (error "VARS* right group cannot be empty"))
    (parse-vars
     (loop for left in left-group append
           (loop for right in right-group
                 collect (intern (format nil "~A~A~A" (dsl-name left) (dsl-name separator) (dsl-name right))
                                 *package*))))))

(defun parse-domain-clause (var body)
  (let ((variable-name (dsl-name var)))
    (unless body
      (error "DOMAIN for ~A requires at least one value or expression" variable-name))
    (cond
      ((and (= (length body) 1)
            (java-enum-domain-token-p (first body)))
       (java-enum-domain-ir (first body)))
      ((and (= (length body) 1)
            (consp (first body)))
       (compile-expr (first body)
                     (make-context nil nil)
                     nil
                     nil
                     :domain-literals-p nil))
      (t
       (list* :set
              (mapcar (lambda (item)
                        (compile-expr item
                                      (make-context nil nil)
                                      nil
                                      nil
                                      :domain-literals-p t))
                      body))))))

(defun java-enum-domain-token-p (value)
  (and (symbolp value)
       (let ((name (symbol-name value)))
         (and (> (length name) 1)
              (char= (char name 0) #\$)))))

(defun java-enum-domain-ir (token)
  (let* ((enum-name (string-downcase (subseq (symbol-name token) 1)))
         (values (gethash enum-name *java-enums*)))
    (unless values
      (error "Unknown Java enum domain reference $~A" enum-name))
    (list* :set (mapcar (lambda (value) (list :lit value)) values))))

(defun parse-domain-star-clause (tail variables domains)
  (unless variables
    (error "DOMAIN* requires VARS or VARS* to be declared first"))
  (unless (and tail (cdr tail))
    (error "DOMAIN* requires a glob pattern and at least one value or expression"))
  (destructuring-bind (pattern &rest body) tail
    (let* ((pattern-name (dsl-name pattern))
           (matches (remove-if-not (lambda (variable)
                                     (wildcard-match-p pattern-name variable))
                                   variables)))
      (unless matches
        (error "DOMAIN* pattern matched no declared variables: ~A" pattern-name))
      (dolist (variable matches)
        (when (gethash variable domains)
          (error "Duplicate DOMAIN clause for variable ~A via DOMAIN*" variable)))
      (let ((compiled-domain (parse-domain-clause pattern body)))
        (loop for variable in matches
              collect (cons variable compiled-domain))))))

(defun parse-named-clause (kind tail)
  (unless (and tail (cdr tail))
    (error "~A clause requires a name and at least one body form" (string-upcase kind)))
  (make-ir-named :name (dsl-name (first tail)) :body (rest tail)))

(defun validate-domain-coverage (variables domains)
  (dolist (variable variables)
    (unless (gethash variable domains)
      (error "Missing DOMAIN clause for variable ~A" variable))))

(defun make-context (variables action-names)
  (list :variables variables :actions action-names))

(defun context-variables (context)
  (getf context :variables))

(defun context-actions (context)
  (getf context :actions))

(defun compile-body (forms context allow-next allow-action-ref)
  (unless forms
    (error "Clause body cannot be empty"))
  (if (= (length forms) 1)
      (compile-expr (first forms) context allow-next allow-action-ref)
      (list* :nary "and"
             (mapcar (lambda (form)
                       (compile-expr form context allow-next allow-action-ref))
                     forms))))

(defun compile-expr (form context allow-next allow-action-ref &key (domain-literals-p nil))
  (cond
    ((numberp form) (list :lit form))
    ((stringp form) (list :lit form))
    ((eq form t) (list :lit t))
    ((null form) (list :lit nil))
    ((symbolp form)
     (compile-symbol-expr form context allow-next allow-action-ref domain-literals-p))
    ((not (consp form))
     (error "Unsupported expression atom ~S" form))
    ((symbol-name= (car form) "quote")
     (unless (= (length form) 2)
       (error "QUOTE expects exactly one argument, got ~S" form))
     (list :lit (quoted-value (second form))))
    ((and (symbol-name= (car form) "set")
          (= (length form) 4)
          (symbol-name= (third form) "as"))
     (compile-set-as-expr form context allow-next allow-action-ref))
    ((symbol-name= (car form) "set")
     (list* :set
            (mapcar (lambda (arg)
                      (compile-expr arg context allow-next allow-action-ref))
                    (cdr form))))
    ((symbol-name= (car form) "not")
     (assert-arity form 2)
     (list :unary "not"
           (compile-expr (second form) context allow-next allow-action-ref)))
    ((symbol-name= (car form) "eventually")
     (assert-arity form 2)
     (list :unary "eventually"
           (compile-expr (second form) context allow-next allow-action-ref)))
    ((symbol-name= (car form) "if")
     (compile-if-then-expr form context allow-next allow-action-ref))
    ((symbol-name= (car form) "assign")
     (compile-assign-expr form context allow-next allow-action-ref))
    ((symbol-name= (car form) "equals")
     (compile-equals-expr form context allow-next allow-action-ref))
    ((symbol-name= (car form) "unchanged*")
     (compile-unchanged-star-expr form context))
    ((member (dsl-name (car form)) '("forall" "exists") :test #'equal)
     (compile-quantified-expr form context allow-next allow-action-ref))
    ((member (dsl-name (car form))
             '("and" "or" "alternate-scenarios" "+" "-" "*" "/" "=" "!=" "<" "<=" ">" ">=" "in" "implies")
             :test #'equal)
     (compile-operator-expr form context allow-next allow-action-ref))
    (t
     (error "Unsupported expression form ~S" form))))

(defun compile-if-then-expr (form context allow-next allow-action-ref)
  (unless (= (length form) 4)
    (error "IF expects the form (if condition then consequence), got ~S" form))
  (unless (symbol-name= (third form) "then")
    (error "IF expects THEN as the third element, got ~S" form))
  (list :nary "and"
        (list (compile-if-branch (second form) context allow-next allow-action-ref)
              (compile-if-branch (fourth form) context allow-next allow-action-ref))))

(defun compile-if-branch (form context allow-next allow-action-ref)
  (if (implicit-and-form-p form)
      (compile-body form context allow-next allow-action-ref)
      (compile-expr form context allow-next allow-action-ref)))

(defun implicit-and-form-p (form)
  (and (listp form)
       (> (length form) 1)
       (every #'consp form)
       (not (and (consp form)
                 (symbolp (car form))
                 (member (dsl-name (car form))
                         '("quote" "set" "not" "eventually" "if" "assign" "equals" "unchanged*"
                           "forall" "exists" "and" "or" "alternate-scenarios"
                           "+" "-" "*" "/" "=" "!=" "<" "<=" ">" ">=" "in" "implies")
                         :test #'equal)))))

(defun compile-assign-expr (form context allow-next allow-action-ref)
  (unless (= (length form) 4)
    (error "ASSIGN expects the form (assign value to variable), got ~S" form))
  (unless (symbol-name= (third form) "to")
    (error "ASSIGN expects TO as the third element, got ~S" form))
  (compile-next-assignment (fourth form) (second form) form context allow-next allow-action-ref))

(defun compile-set-as-expr (form context allow-next allow-action-ref)
  (unless (= (length form) 4)
    (error "SET-AS expects the form (set variable as value), got ~S" form))
  (unless (symbol-name= (third form) "as")
    (error "SET-AS expects AS as the third element, got ~S" form))
  (compile-next-assignment (second form) (fourth form) form context allow-next allow-action-ref))

(defun compile-next-assignment (target value source-form context allow-next allow-action-ref)
  (declare (ignore allow-next))
  (let ((target-name (dsl-name target)))
    (unless (member target-name (context-variables context) :test #'equal)
      (error "Assignment target must be a declared variable name, got ~S in ~S" target source-form))
    (list :binary "="
          (list :next target-name)
          (compile-expr value context t allow-action-ref))))

(defun compile-equals-expr (form context allow-next allow-action-ref)
  (unless (= (length form) 3)
    (error "EQUALS expects exactly two arguments, got ~S" form))
  (list :binary "="
        (compile-expr (second form) context allow-next allow-action-ref)
        (compile-expr (third form) context allow-next allow-action-ref)))

(defun compile-unchanged-star-expr (form context)
  (unless (> (length form) 1)
    (error "UNCHANGED* expects at least one glob pattern, got ~S" form))
  (let ((seen nil)
        (clauses nil))
    (dolist (pattern (rest form))
      (let* ((pattern-name (dsl-name pattern))
             (matches (remove-if-not (lambda (variable)
                                       (wildcard-match-p pattern-name variable))
                                     (context-variables context))))
        (unless matches
          (error "UNCHANGED* pattern matched no declared variables: ~A" pattern-name))
        (dolist (variable matches)
          (unless (member variable seen :test #'equal)
            (push variable seen)
            (push (list :binary "="
                        (list :next variable)
                        (list :var variable))
                  clauses)))))
    (list* :nary "and" (nreverse clauses))))

(defun compile-symbol-expr (symbol context allow-next allow-action-ref domain-literals-p)
  (let* ((name (dsl-name symbol))
         (next-name (and (plus-suffixed-name-p name)
                         (subseq name 0 (1- (length name)))))
         (action-name (and (> (length name) 1)
                           (or (char= (char name 0) #\@)
                               (char= (char name 0) #\$))
                           (subseq name 1))))
    (cond
      (domain-literals-p
       (list :lit name))
      ((member name (context-variables context) :test #'equal)
       (list :var name))
      ((and allow-next
            next-name
            (member next-name (context-variables context) :test #'equal))
       (list :next next-name))
      ((and allow-action-ref
            action-name
            (member action-name (context-actions context) :test #'equal))
       (list :action-ref action-name))
      (t
       (list :lit name)))))

(defun compile-quantified-expr (form context allow-next allow-action-ref)
  (destructuring-bind (op binding body) form
    (unless (and (consp binding)
                 (= (length binding) 3)
                 (symbolp (first binding))
                 (symbol-name= (second binding) "in"))
      (error "~A binding must look like (var in domain), got ~S" op binding))
    (let ((var-name (dsl-name (first binding))))
      (list :quantified
            (dsl-name op)
            var-name
            (compile-expr (third binding) context allow-next allow-action-ref)
            (compile-expr body context allow-next allow-action-ref)))))

(defun compile-operator-expr (form context allow-next allow-action-ref)
  (let* ((op (dsl-name (car form)))
         (normalized-op (if (string= op "alternate-scenarios") "or" op))
         (args (mapcar (lambda (arg)
                         (compile-expr arg context allow-next allow-action-ref))
                       (cdr form))))
    (cond
      ((member normalized-op '("=" "!=" "<" "<=" ">" ">=" "in" "implies") :test #'equal)
       (unless (= (length args) 2)
         (error "~A expects exactly two arguments, got ~S" normalized-op form))
       (list :binary normalized-op (first args) (second args)))
      (t
       (unless args
         (error "~A expects at least one argument, got ~S" normalized-op form))
       (list* :nary normalized-op args)))))

(defun spec-ir->json (spec)
  (jobject
   (jpair "name" (ir-spec-name spec))
   (jpair "variables" (jarray-from-list (ir-spec-variables spec)))
   (jpair "domains" (jobject-from-alist
                     (mapcar (lambda (entry)
                               (cons (car entry) (expr-ir->json (cdr entry))))
                             (ir-spec-domains spec))))
   (jpair "init" (expr-ir->json (ir-spec-init spec)))
   (jpair "actions" (jarray-from-list
                     (mapcar #'named-ir->json (ir-spec-actions spec))))
   (jpair "next" (expr-ir->json (ir-spec-next spec)))
   (jpair "invariants" (jarray-from-list
                        (mapcar #'named-ir->json (ir-spec-invariants spec))))
   (jpair "properties" (jarray-from-list
                        (mapcar #'named-ir->json (ir-spec-properties spec))))))

(defun named-ir->json (named)
  (jobject
   (jpair "name" (ir-named-name named))
   (jpair "body" (expr-ir->json (ir-named-body named)))))

(defun expr-ir->json (expr)
  (case (first expr)
    (:lit (jobject (jpair "lit" (second expr))))
    (:var (jobject (jpair "var" (second expr))))
    (:next (jobject (jpair "next" (second expr))))
    (:action-ref (jobject (jpair "actionRef" (second expr))))
    (:set (jobject (jpair "set" (jarray-from-list (mapcar #'expr-ir->json (rest expr))))))
    (:unary (jobject (jpair (second expr) (expr-ir->json (third expr)))))
    (:binary (jobject (jpair (second expr)
                             (jarray-from-list
                              (list (expr-ir->json (third expr))
                                    (expr-ir->json (fourth expr)))))))
    (:nary (jobject (jpair (second expr)
                           (jarray-from-list (mapcar #'expr-ir->json (cddr expr))))))
    (:quantified
     (jobject
      (jpair (second expr)
             (jobject
              (jpair "var" (third expr))
              (jpair "in" (expr-ir->json (fourth expr)))
              (jpair "body" (expr-ir->json (fifth expr)))))))
    (otherwise
     (error "Unknown IR expression tag ~S" (first expr)))))

(defun jobject (&rest pairs)
  (cons :object pairs))

(defun jpair (name value)
  (list name value))

(defun jarray-from-list (items)
  (cons :array items))

(defun jobject-from-alist (alist)
  (cons :object
        (mapcar (lambda (entry)
                  (list (car entry) (cdr entry)))
                alist)))

(defun write-json (node stream indent)
  (cond
    ((and (consp node) (eq (car node) :object))
     (write-json-object (cdr node) stream indent))
    ((and (consp node) (eq (car node) :array))
     (write-json-array (cdr node) stream indent))
    ((stringp node)
     (write-json-string node stream))
    ((numberp node)
     (princ node stream))
    ((eq node t)
     (princ "true" stream))
    ((null node)
     (princ "false" stream))
    (t
     (error "Cannot serialize ~S to JSON" node))))

(defun write-json-object (pairs stream indent)
  (princ "{" stream)
  (if (null pairs)
      (princ "}" stream)
      (progn
        (loop for pair in pairs
              for firstp = t then nil
              do (unless firstp
                   (princ "," stream))
                 (terpri stream)
                 (write-indentation stream (+ indent 2))
                 (write-json-string (first pair) stream)
                 (princ ": " stream)
                 (write-json (second pair) stream (+ indent 2)))
        (terpri stream)
        (write-indentation stream indent)
        (princ "}" stream))))

(defun write-json-array (items stream indent)
  (princ "[" stream)
  (if (null items)
      (princ "]" stream)
      (progn
        (loop for item in items
              for firstp = t then nil
              do (unless firstp
                   (princ "," stream))
                 (terpri stream)
                 (write-indentation stream (+ indent 2))
                 (write-json item stream (+ indent 2)))
        (terpri stream)
        (write-indentation stream indent)
        (princ "]" stream))))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for ch across string
        do (case ch
             (#\" (princ "\\\"" stream))
             (#\\ (princ "\\\\" stream))
             (#\Newline (princ "\\n" stream))
             (#\Return (princ "\\r" stream))
             (#\Tab (princ "\\t" stream))
             (otherwise (write-char ch stream))))
  (write-char #\" stream))

(defun write-indentation (stream indent)
  (dotimes (_ indent)
    (declare (ignore _))
    (write-char #\Space stream)))

(defun dsl-name (thing)
  (etypecase thing
    (symbol (string-downcase (symbol-name thing)))
    (string thing)))

(defun symbol-name= (symbol string)
  (and (symbolp symbol)
       (string-equal (symbol-name symbol) string)))

(defun plus-suffixed-name-p (name)
  (and (> (length name) 1)
       (char= (char name (1- (length name))) #\+)))

(defun percent-macro-head-p (thing)
  (and (symbolp thing)
       (> (length (symbol-name thing)) 1)
       (char= (char (symbol-name thing) 0) #\%)))

(defparameter *reserved-dsl-head-names*
  '("system" "vars" "domain" "init" "action" "next" "invariant" "property"
    "vars*" "domain*"
    "quote" "set" "not" "eventually" "if" "assign" "equals" "unchanged*" "forall" "exists"
    "and" "or" "alternate-scenarios" "+" "-" "*" "/" "=" "!=" "<" "<=" ">" ">=" "in" "implies"
    "expand"))

(defun dsl-macro-call-p (form)
  (and (consp form)
       (symbolp (car form))
       (not (member (dsl-name (car form)) *reserved-dsl-head-names* :test #'equal))
       (macro-function (car form))))

(defun bang-macro-head-p (thing)
  (and (symbolp thing)
       (let ((name (symbol-name thing)))
         (and (> (length name) 1)
              (char= (char name 0) #\!)
              (not (string= name "!="))))))

(defun quoted-value (thing)
  (etypecase thing
    (symbol (dsl-name thing))
    (string thing)
    (number thing)
    ((eql t) t)
    (null nil)))

(defun assert-arity (form expected)
  (unless (= (length form) expected)
    (error "~A expects ~D element(s), got ~S" (car form) expected form)))

(defun ensure-directory-pathname (path)
  (uiop:ensure-directory-pathname (pathname path)))

(main)
