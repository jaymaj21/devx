cd fastest-speed-java
javac mprewriter.java
javac Main.java
echo "Timing without stack depth"
java -Dmprewriter.depthMode=constant Main
echo "Timing with stack depth"
java -Dmprewriter.depthMode=stack Main


