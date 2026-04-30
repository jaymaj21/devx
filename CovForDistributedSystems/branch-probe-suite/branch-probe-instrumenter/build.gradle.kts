plugins {
    `java`
    id("com.github.johnrengelman.shadow") version "8.1.1"
}

group = "com.jm.cov"
version = "1.0.0"

tasks.jar {
    archiveBaseName.set("branch-probe-instrumenter")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

dependencies {
    implementation("org.ow2.asm:asm:9.6")
    implementation("org.ow2.asm:asm-commons:9.6")
}

// Produce a fat JAR like Maven Assembly/Shade (*-jar-with-dependencies.jar)
tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    archiveBaseName.set("branch-probe-instrumenter")
    archiveClassifier.set("jar-with-dependencies")
}
// Keep standard thin jar too; make 'build' produce both
tasks.build {
    dependsOn(tasks.shadowJar)
}

