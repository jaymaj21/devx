./gradlew clean

cd ./branch-probe-demoapp; mvn clean
cd ..
cd ./branch-probe-instrumenter; mvn clean
cd ..
cd ./branch-probe-suite/branch-probe-instrumenter; mvn clean
cd ../..
cd ./branch-probe-suite/mprewriter-runtime; mvn clean
cd ../..
cd ./branch-probe-suite; mvn clean
cd ..
cd ./code-analytics; mvn clean
cd ..
cd ./JavaAppWithUdpProbes; mvn clean
cd ..

echo zip -e  -r java_sources.zip *.bat  *.sh *.kts *.md ./branch-probe-demoapp ./branch-probe-fractal-demoapp ./branch-probe-instrumenter ./branch-probe-suite ./code-analytics ./JavaAppWithUdpProbes ./java-fractal-demo ./gradle gradlew gradlew.bat




