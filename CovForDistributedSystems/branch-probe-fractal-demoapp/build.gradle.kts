plugins {
    `java`
}

group = "com.example"
version = "1.0.0"

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

// Repositories are defined centrally in root settings.gradle.kts

tasks.jar {
    archiveBaseName.set("branch-probe-fractal-demoapp")
    manifest.attributes(mapOf("Main-Class" to "com.example.fractaldemo.Main"))
}
