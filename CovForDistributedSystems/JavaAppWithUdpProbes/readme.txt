D:\java_testbed\java_app_with_clojure>mvn dependency:copy-dependencies
[INFO] Scanning for projects...
[INFO]
[INFO] ---------------------< com.trading:TradingSystem >----------------------
[INFO] Building TradingSystem 1.0-SNAPSHOT
[INFO] --------------------------------[ jar ]---------------------------------
[INFO]
[INFO] --- maven-dependency-plugin:2.8:copy-dependencies (default-cli) @ TradingSystem ---
[WARNING] The artifact xml-apis:xml-apis:jar:2.0.2 has been relocated to xml-apis:xml-apis:jar:1.0.b2
[INFO] Copying junit-jupiter-engine-5.7.1.jar to D:\java_testbed\java_app_with_clojure\target\dependency\junit-jupiter-engine-5.7.1.jar
[INFO] Copying opentest4j-1.2.0.jar to D:\java_testbed\java_app_with_clojure\target\dependency\opentest4j-1.2.0.jar
[INFO] Copying apiguardian-api-1.1.0.jar to D:\java_testbed\java_app_with_clojure\target\dependency\apiguardian-api-1.1.0.jar
[INFO] Copying junit-jupiter-api-5.7.1.jar to D:\java_testbed\java_app_with_clojure\target\dependency\junit-jupiter-api-5.7.1.jar
[INFO] Copying core.specs.alpha-0.2.62.jar to D:\java_testbed\java_app_with_clojure\target\dependency\core.specs.alpha-0.2.62.jar
[INFO] Copying junit-platform-commons-1.7.1.jar to D:\java_testbed\java_app_with_clojure\target\dependency\junit-platform-commons-1.7.1.jar
[INFO] Copying clojure-1.11.3.jar to D:\java_testbed\java_app_with_clojure\target\dependency\clojure-1.11.3.jar
[INFO] Copying spec.alpha-0.3.218.jar to D:\java_testbed\java_app_with_clojure\target\dependency\spec.alpha-0.3.218.jar
[INFO] Copying junit-platform-engine-1.7.1.jar to D:\java_testbed\java_app_with_clojure\target\dependency\junit-platform-engine-1.7.1.jar
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  2.470 s
[INFO] Finished at: 2025-03-20T02:51:14Z
[INFO] ------------------------------------------------------------------------

D:\java_testbed\java_app_with_clojure>java -cp "target/classes;target/dependency/*" clojure.main
Clojure 1.11.3
user=> (ns my-clojure-app.core
  (:import [com.trading.messagehandler MarketDataHandlerImpl]))
nil
my-clojure-app.core=> (println (MarketDataHandlerImpl/factorial 10))
3628800
nil
my-clojure-app.core=>
^C
