plugins {
    `java`
}

group = "com.jm.cov"
version = "1.0.0"

tasks.jar {
    archiveBaseName.set("mprewriter-runtime")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

dependencies {
}

