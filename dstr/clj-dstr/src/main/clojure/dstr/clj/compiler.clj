(ns dstr.clj.compiler
  (:require [clojure.java.io :as io]
            [clojure.string :as str]))

(declare compile-system-form)

(def ^:dynamic *compiled-system* nil)
(def ^:dynamic *source-dir* nil)
(def ^:dynamic *input-ns* nil)

(def clause-heads
  '#{vars vars* domain domain* init action next invariant property})

(def reserved-heads
  '#{system vars vars* domain domain* init action next invariant property
     quote set not eventually if assign equals unchanged* forall exists
     action-ref @ deref and or alternate-scenarios + - * / = != < <= > >= in
     implies})

(defmacro system [name & clauses]
  (let [input-ns-name (ns-name *ns*)]
    `(binding [*input-ns* (the-ns '~input-ns-name)]
       (set! *compiled-system*
             (compile-system-form
              (quote ~(cons 'system (cons name clauses))))))))

(defn next-var-symbol [symbol]
  (when-not (symbol? symbol)
    (throw (ex-info "Expected symbol for next-state suffixing" {:value symbol})))
  (symbol (str (name symbol) "+")))

(defmacro same [var]
  (list '= (next-var-symbol var) var))

(defmacro unchanged [& vars]
  (mapv (fn [var] (list '= (next-var-symbol var) var)) vars))

(defn include [path]
  (let [file (io/file path)
        resolved (if (.isAbsolute file)
                   file
                   (io/file (or *source-dir* ".") path))]
    (load-file (.getPath resolved))))

(defn dsl-name [value]
  (cond
    (symbol? value) (name value)
    (keyword? value) (name value)
    (string? value) value
    :else (str value)))

(defn symbol-name? [value expected]
  (and (symbol? value) (= (name value) expected)))

(defn plus-suffixed-name? [value]
  (and (seq value) (str/ends-with? value "+")))

(defn action-ref-form? [form]
  (and (seq? form)
       (= 2 (count form))
       (let [head (first form)]
         (or (symbol-name? head "action-ref")
             (symbol-name? head "@")
             (and (symbol? head)
                  (= "deref" (name head)))))))

(defn action-ref-name [form]
  (dsl-name (second form)))

(defn macro-call? [form]
  (and (seq? form)
       (symbol? (first form))
       (not (contains? reserved-heads (symbol (name (first form)))))
       (when-let [resolved (ns-resolve (or *input-ns* *ns*) (first form))]
         (:macro (meta resolved)))))

(declare expand-special-form)

(defn sibling-form-list? [value]
  (and (sequential? value)
       (seq value)
       (every? sequential? value)
       (sequential? (first value))))

(defn expand-special-forms-list [forms]
  (mapcat (fn [form]
            (let [expanded (expand-special-form form)]
              (if (sibling-form-list? expanded)
                expanded
                [expanded])))
          forms))

(defn clause-list? [value]
  (and (sequential? value)
       (seq value)
       (every? sequential? value)
       (every? #(contains? clause-heads (symbol (name (first %)))) value)))

(defn expand-system-clauses [clauses]
  (expand-special-forms-list clauses))

(defn expand-special-form [form]
  (cond
    (not (seq? form)) form
    (symbol-name? (first form) "quote") form
    (macro-call? form) (expand-special-form (macroexpand-1 form))
    (action-ref-form? form) form
    :else (apply list (first form) (expand-special-forms-list (rest form)))))

(defn parse-vars [vars]
  (when (empty? vars)
    (throw (ex-info "vars requires at least one variable" {})))
  (let [names (mapv dsl-name vars)]
    (when (not= (count names) (count (distinct names)))
      (throw (ex-info "Duplicate variable name in vars clause" {:vars vars})))
    names))

(defn parse-vars-product [args]
  (when-not (= 4 (count args))
    (throw (ex-info "vars* expects: (vars* separator (group1 ...) * (group2 ...))" {:args args})))
  (let [[separator left-group marker right-group] args]
    (when-not (= "*" (dsl-name marker))
      (throw (ex-info "vars* expects * as the third argument" {:marker marker})))
    (when-not (and (sequential? left-group) (sequential? right-group)
                   (seq left-group) (seq right-group))
      (throw (ex-info "vars* requires two non-empty groups" {:args args})))
    (parse-vars
     (for [left left-group
           right right-group]
       (symbol (str (dsl-name left) (dsl-name separator) (dsl-name right)))))))

(defn wildcard-match? [pattern text]
  (letfn [(match-at [pattern-index text-index]
            (cond
              (= pattern-index (count pattern))
              (= text-index (count text))

              (= \* (nth pattern pattern-index))
              (or (match-at (inc pattern-index) text-index)
                  (and (< text-index (count text))
                       (match-at pattern-index (inc text-index))))

              (= \? (nth pattern pattern-index))
              (and (< text-index (count text))
                   (match-at (inc pattern-index) (inc text-index)))

              :else
              (and (< text-index (count text))
                   (= (Character/toLowerCase ^char (nth pattern pattern-index))
                      (Character/toLowerCase ^char (nth text text-index)))
                   (match-at (inc pattern-index) (inc text-index)))))]
    (match-at 0 0)))

(defn context [variables actions]
  {:variables (set variables)
   :action-names (set actions)
   :locals #{}})

(declare compile-expr)

(defn compile-body [forms ctx allow-next? allow-action-ref?]
  (when (empty? forms)
    (throw (ex-info "Clause body cannot be empty" {})))
  (if (= 1 (count forms))
    (compile-expr (first forms) ctx allow-next? allow-action-ref?)
    {"and" (mapv #(compile-expr % ctx allow-next? allow-action-ref?) forms)}))

(defn compile-domain [body]
  (if (and (= 1 (count body)) (seq? (first body)))
    (compile-expr (first body) (context [] []) false false)
    {"set" (mapv #(compile-expr % (context [] []) false false :domain-literal? true) body)}))

(defn parse-domain-star [args variables domains]
  (when (empty? variables)
    (throw (ex-info "domain* requires vars or vars* to be declared first" {})))
  (when (< (count args) 2)
    (throw (ex-info "domain* requires a glob pattern and at least one value" {:args args})))
  (let [pattern (dsl-name (first args))
        body (rest args)
        matches (filterv #(wildcard-match? pattern %) variables)]
    (when (empty? matches)
      (throw (ex-info "domain* pattern matched no declared variables" {:pattern pattern})))
    (doseq [variable matches]
      (when (contains? domains variable)
        (throw (ex-info "Duplicate domain clause via domain*" {:variable variable}))))
    (into {} (map (fn [variable] [variable (compile-domain body)]) matches))))

(defn named-clause [kind args]
  (when (< (count args) 2)
    (throw (ex-info (str kind " requires a name and at least one body form") {:args args})))
  {:name (dsl-name (first args))
   :body (vec (rest args))})

(defn implicit-and-form? [form]
  (and (sequential? form)
       (> (count form) 1)
       (every? sequential? form)
       (not (contains? reserved-heads (symbol (name (first form)))))))

(defn compile-if-branch [form ctx allow-next? allow-action-ref?]
  (if (implicit-and-form? form)
    (compile-body form ctx allow-next? allow-action-ref?)
    (compile-expr form ctx allow-next? allow-action-ref?)))

(defn split-if-form [form]
  (let [body (rest form)
        before-then (take-while #(not (symbol-name? % "then")) body)
        after-then (rest (drop-while #(not (symbol-name? % "then")) body))]
    (when (or (= (count before-then) (count body))
              (empty? before-then)
              (empty? after-then))
      (throw (ex-info "if expects: (if condition then consequence)" {:form form})))
    [before-then after-then]))

(defn compile-next-assignment [target value source-form ctx allow-next? allow-action-ref?]
  (let [target-name (dsl-name target)]
    (when-not (contains? (:variables ctx) target-name)
      (throw (ex-info "Assignment target must be a declared variable"
                      {:target target :form source-form})))
    {"=" [{"next" target-name}
          (compile-expr value ctx allow-next? allow-action-ref?)]}))

(defn compile-quantified [form ctx allow-next? allow-action-ref?]
  (let [[op binding body] form]
    (when-not (and (sequential? binding)
                   (= 3 (count binding))
                   (symbol-name? (second binding) "in"))
      (throw (ex-info "Quantifier binding must look like (var in domain)" {:form form})))
    (let [var-name (dsl-name (first binding))
          next-ctx (update ctx :locals conj var-name)]
      {(dsl-name op) {"var" var-name
                      "in" (compile-expr (nth binding 2) ctx allow-next? allow-action-ref?)
                      "body" (compile-expr body next-ctx allow-next? allow-action-ref?)}})))

(defn compile-symbol [symbol ctx allow-next? allow-action-ref? domain-literal?]
  (let [name (dsl-name symbol)]
    (cond
      (= name "t") {"lit" true}
      domain-literal? {"lit" name}
      (contains? (:locals ctx) name) {"var" name}
      (contains? (:variables ctx) name) {"var" name}
      (and allow-next? (plus-suffixed-name? name)
           (contains? (:variables ctx) (subs name 0 (dec (count name)))))
      {"next" (subs name 0 (dec (count name)))}
      (and allow-action-ref? (str/starts-with? name "@")
           (contains? (:action-names ctx) (subs name 1)))
      {"actionRef" (subs name 1)}
      (and allow-action-ref? (str/starts-with? name "$")
           (contains? (:action-names ctx) (subs name 1)))
      {"actionRef" (subs name 1)}
      :else {"lit" name})))

(defn compile-operator [form ctx allow-next? allow-action-ref?]
  (let [op (dsl-name (first form))
        normalized (if (= op "alternate-scenarios") "or" op)
        args (mapv #(compile-expr % ctx allow-next? allow-action-ref?) (rest form))]
    (if (contains? #{"=" "!=" "<" "<=" ">" ">=" "in" "implies"} normalized)
      (do
        (when-not (= 2 (count args))
          (throw (ex-info "Binary operator expects exactly two arguments" {:form form})))
        {normalized args})
      (do
        (when (empty? args)
          (throw (ex-info "Operator expects at least one argument" {:form form})))
        {normalized args}))))

(defn compile-expr
  ([form ctx allow-next? allow-action-ref?]
   (compile-expr form ctx allow-next? allow-action-ref? :domain-literal? false))
  ([form ctx allow-next? allow-action-ref? & {:keys [domain-literal?] :or {domain-literal? false}}]
   (cond
     (number? form) {"lit" form}
     (string? form) {"lit" form}
     (true? form) {"lit" true}
     (false? form) {"lit" false}
     (nil? form) {"lit" false}
     (symbol? form) (compile-symbol form ctx allow-next? allow-action-ref? domain-literal?)
     (action-ref-form? form) {"actionRef" (action-ref-name form)}
     (not (seq? form)) {"lit" (dsl-name form)}
     :else
     (let [head (first form)]
       (cond
         (symbol-name? head "quote")
         (do
           (when-not (= 2 (count form))
             (throw (ex-info "quote expects exactly one argument" {:form form})))
           {"lit" (dsl-name (second form))})

         (and (symbol-name? head "set")
              (= 4 (count form))
              (symbol-name? (nth form 2) "as"))
         (compile-next-assignment (second form) (nth form 3) form ctx allow-next? allow-action-ref?)

         (symbol-name? head "set")
         {"set" (mapv #(compile-expr % ctx allow-next? allow-action-ref?) (rest form))}

         (contains? #{"not" "eventually"} (dsl-name head))
         (do
           (when-not (= 2 (count form))
             (throw (ex-info "Unary operator expects one argument" {:form form})))
           {(dsl-name head) (compile-expr (second form) ctx allow-next? allow-action-ref?)})

         (symbol-name? head "if")
         (let [[condition consequence] (split-if-form form)]
           {"and" [(compile-body condition ctx allow-next? allow-action-ref?)
                   (compile-body consequence ctx allow-next? allow-action-ref?)]})

         (symbol-name? head "assign")
         (do
           (when-not (and (= 4 (count form)) (symbol-name? (nth form 2) "to"))
             (throw (ex-info "assign expects: (assign value to variable)" {:form form})))
           (compile-next-assignment (nth form 3) (second form) form ctx allow-next? allow-action-ref?))

         (symbol-name? head "equals")
         (do
           (when-not (= 3 (count form))
             (throw (ex-info "equals expects two arguments" {:form form})))
           {"=" [(compile-expr (second form) ctx allow-next? allow-action-ref?)
                 (compile-expr (nth form 2) ctx allow-next? allow-action-ref?)]})

         (symbol-name? head "unchanged*")
         (let [patterns (rest form)
               variables (:variables ctx)
               matches (distinct
                        (mapcat (fn [pattern]
                                  (let [pattern-name (dsl-name pattern)
                                        matched (filter #(wildcard-match? pattern-name %) variables)]
                                    (when (empty? matched)
                                      (throw (ex-info "unchanged* pattern matched no declared variables"
                                                      {:pattern pattern-name})))
                                    matched))
                                patterns))]
           {"and" (mapv (fn [variable] {"=" [{"next" variable} {"var" variable}]}) matches)})

         (contains? #{"forall" "exists"} (dsl-name head))
         (compile-quantified form ctx allow-next? allow-action-ref?)

         (contains? #{"and" "or" "alternate-scenarios" "+" "-" "*" "/" "=" "!=" "<" "<=" ">" ">=" "in" "implies"} (dsl-name head))
         (compile-operator form ctx allow-next? allow-action-ref?)

         :else
         (throw (ex-info "Unsupported expression form" {:form form})))))))

(defn compile-system-form [form]
  (when-not (and (seq? form) (symbol-name? (first form) "system"))
    (throw (ex-info "Top-level form must be a system form" {:form form})))
  (let [[_ raw-name & raw-clauses] form
        clauses (expand-system-clauses raw-clauses)]
    (loop [clauses clauses
           variables nil
           domains {}
           actions []
           invariants []
           properties []
           init nil
           next nil]
      (if (empty? clauses)
        (do
          (when-not variables
            (throw (ex-info "system requires a vars clause" {})))
          (when-not init
            (throw (ex-info "system requires an init clause" {})))
          (when-not next
            (throw (ex-info "system requires a next clause" {})))
          (doseq [variable variables]
            (when-not (contains? domains variable)
              (throw (ex-info "Missing domain clause" {:variable variable}))))
          (let [action-names (mapv :name actions)
                ctx (context variables action-names)]
            {"name" (dsl-name raw-name)
             "variables" variables
             "domains" (into {} (map (fn [variable] [variable (domains variable)]) variables))
             "init" (compile-body init ctx false false)
             "actions" (mapv (fn [{:keys [name body]}]
                               {"name" name
                                "body" (compile-body body ctx true false)})
                             actions)
             "next" (compile-body next ctx true true)
             "invariants" (mapv (fn [{:keys [name body]}]
                                   {"name" name
                                    "body" (compile-body body ctx false false)})
                                 invariants)
             "properties" (mapv (fn [{:keys [name body]}]
                                   {"name" name
                                    "body" (compile-body body ctx false false)})
                                 properties)}))
        (let [clause (first clauses)
              head (first clause)
              args (rest clause)]
          (case (symbol (name head))
            vars
            (do
              (when variables
                (throw (ex-info "Only one vars clause is allowed" {})))
              (recur (rest clauses) (parse-vars args) domains actions invariants properties init next))

            vars*
            (do
              (when variables
                (throw (ex-info "Only one vars clause is allowed" {})))
              (recur (rest clauses) (parse-vars-product args) domains actions invariants properties init next))

            domain
            (let [variable (dsl-name (first args))]
              (when (contains? domains variable)
                (throw (ex-info "Duplicate domain clause" {:variable variable})))
              (recur (rest clauses) variables (assoc domains variable (compile-domain (rest args)))
                     actions invariants properties init next))

            domain*
            (recur (rest clauses) variables (merge domains (parse-domain-star args variables domains))
                   actions invariants properties init next)

            init
            (do
              (when init
                (throw (ex-info "Only one init clause is allowed" {})))
              (recur (rest clauses) variables domains actions invariants properties (vec args) next))

            next
            (do
              (when next
                (throw (ex-info "Only one next clause is allowed" {})))
              (recur (rest clauses) variables domains actions invariants properties init (vec args)))

            action
            (recur (rest clauses) variables domains (conj actions (named-clause "action" args))
                   invariants properties init next)

            invariant
            (recur (rest clauses) variables domains actions
                   (conj invariants (named-clause "invariant" args)) properties init next)

            property
            (recur (rest clauses) variables domains actions invariants
                   (conj properties (named-clause "property" args)) init next)

            (throw (ex-info "Unknown system clause" {:clause clause}))))))))

(defn json-escape [value]
  (-> (str value)
      (str/replace "\\" "\\\\")
      (str/replace "\"" "\\\"")
      (str/replace "\n" "\\n")
      (str/replace "\r" "\\r")
      (str/replace "\t" "\\t")))

(declare write-json)

(defn write-json-array [items indent]
  (if (empty? items)
    "[]"
    (str "[\n"
         (str/join ",\n"
                   (map #(str (apply str (repeat (+ indent 2) " "))
                              (write-json % (+ indent 2)))
                        items))
         "\n"
         (apply str (repeat indent " "))
         "]")))

(defn write-json-object [m indent]
  (if (empty? m)
    "{}"
    (str "{\n"
         (str/join ",\n"
                   (map (fn [[k v]]
                          (str (apply str (repeat (+ indent 2) " "))
                               "\"" (json-escape k) "\": "
                               (write-json v (+ indent 2))))
                        m))
         "\n"
         (apply str (repeat indent " "))
         "}")))

(defn write-json [value indent]
  (cond
    (map? value) (write-json-object value indent)
    (sequential? value) (write-json-array value indent)
    (string? value) (str "\"" (json-escape value) "\"")
    (number? value) (str value)
    (true? value) "true"
    (false? value) "false"
    (nil? value) "false"
    :else (str "\"" (json-escape value) "\"")))

(defn ensure-parent-dir [path]
  (when-let [parent (.getParentFile (io/file path))]
    (.mkdirs parent)))

(defn output-path-for [input output]
  (if output
    output
    (str/replace input #"\.[^.\\\/]+$" ".json")))

(defn compile-one-file [input output]
  (let [input-file (io/file input)
        output-file (output-path-for (.getPath input-file) output)
        ns-sym (symbol (str "dstr.clj.input." (gensym "spec")))
        target-ns (create-ns ns-sym)]
    (binding [*compiled-system* nil
              *source-dir* (.getParentFile (.getAbsoluteFile input-file))
              *input-ns* target-ns
              *ns* target-ns]
      (clojure.core/refer 'clojure.core)
      (clojure.core/refer 'dstr.clj.compiler
                          :only '[system same unchanged include next-var-symbol])
      (load-file (.getPath input-file))
      (when-not *compiled-system*
        (throw (ex-info "Input must contain a top-level system form" {:input input})))
      (ensure-parent-dir output-file)
      (spit output-file (str (write-json *compiled-system* 0) "\n"))
      (println "Wrote" output-file))))

(defn compile-directory [input-dir output-dir]
  (let [dir (io/file input-dir)
        target-dir (io/file (or output-dir input-dir))
        files (sort-by #(.getName %) (filter #(.endsWith (.getName %) ".cdstr")
                                             (file-seq dir)))]
    (when (empty? files)
      (throw (ex-info "No .cdstr files found" {:directory input-dir})))
    (.mkdirs target-dir)
    (doseq [file files]
      (let [base (str/replace (.getName file) #"\.cdstr$" ".json")]
        (compile-one-file (.getPath file) (.getPath (io/file target-dir base)))))))

(defn compile-input-path [input output]
  (let [file (io/file input)]
    (cond
      (.isDirectory file) (compile-directory input output)
      (.endsWith (.getName file) ".cdstr") (compile-one-file input output)
      :else (throw (ex-info "Input must be a .cdstr file or directory" {:input input})))))

(defn usage []
  (binding [*out* *err*]
    (println "Usage: clj-dstr <input.cdstr|directory> [output.json|directory]")))

(defn cause-messages [throwable]
  (take-while some? (iterate #(.getCause ^Throwable %) throwable)))

(defn -main [& args]
  (try
    (cond
      (or (empty? args) (some #{"--help" "-h"} args))
      (do
        (usage)
        (System/exit (if (empty? args) 1 0)))

      (= 1 (count args))
      (compile-input-path (first args) nil)

      (= 2 (count args))
      (compile-input-path (first args) (second args))

      :else
      (throw (ex-info "Expected one input path and an optional output path" {:args args})))
    (catch Throwable t
      (binding [*out* *err*]
        (println "Error:" (.getMessage t))
        (doseq [cause (rest (cause-messages t))]
          (println "Caused by:" (.getMessage ^Throwable cause))
          (when-let [data (ex-data cause)]
            (println data)))
        (when-let [data (ex-data t)]
          (println data)))
      (System/exit 1))))
