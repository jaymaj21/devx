plugins {
    `java`
}

group = "com.example"
version = "1.0-SNAPSHOT"

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

// Note: repositories are defined centrally in settings.gradle.kts

tasks.jar {
    archiveBaseName.set("java-fractal-demo")
}
