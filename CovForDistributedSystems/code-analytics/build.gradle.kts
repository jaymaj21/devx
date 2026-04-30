plugins {
    `java`
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "com.codeanalytics"
version = "1.0-SNAPSHOT"

tasks.jar {
    archiveBaseName.set("clojure-shell")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

dependencies {
    implementation("org.clojure:clojure:1.11.1")
    implementation("org.jline:jline:3.21.0")
}

// Produce a fat JAR like Maven Assembly/Shade (*-jar-with-dependencies.jar)
tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    archiveBaseName.set("clojure-shell")
    archiveClassifier.set("jar-with-dependencies")
}
// Keep standard thin jar too; make 'build' produce both
tasks.build {
    dependsOn(tasks.shadowJar)
}

