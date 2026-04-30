plugins {
    `java`
}

group = "com.example"
version = "1.0.0"

tasks.jar {
    archiveBaseName.set("branch-probe-demoapp")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

dependencies {
}

