pluginManagement { repositories { mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
  repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
  repositories {
    mavenCentral()
  }
}
include(":JavaAppWithUdpProbes")
project(":JavaAppWithUdpProbes").projectDir = file("JavaAppWithUdpProbes")
include(":branch-probe-demoapp")
project(":branch-probe-demoapp").projectDir = file("branch-probe-demoapp")
include(":branch-probe-instrumenter")
project(":branch-probe-instrumenter").projectDir = file("branch-probe-instrumenter")
include(":branch-probe-suite")
project(":branch-probe-suite").projectDir = file("branch-probe-suite")
include(":code-analytics")
project(":code-analytics").projectDir = file("code-analytics")
include(":java-fractal-demo")
project(":java-fractal-demo").projectDir = file("java-fractal-demo")
include(":branch-probe-fractal-demoapp")
project(":branch-probe-fractal-demoapp").projectDir = file("branch-probe-fractal-demoapp")
include(":branch-probe-suite:mprewriter-runtime")
project(":branch-probe-suite:mprewriter-runtime").projectDir = file("branch-probe-suite/mprewriter-runtime")
include(":branch-probe-instrumenter")
project(":branch-probe-instrumenter").projectDir = file("branch-probe-instrumenter")
