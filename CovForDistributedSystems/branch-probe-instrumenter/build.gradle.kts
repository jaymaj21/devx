plugins {
    `java`
}

group = "demo"
version = "1.3.0"

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
val fatJar by tasks.registering(Jar::class) {
    archiveBaseName.set("branch-probe-instrumenter")
    archiveClassifier.set("jar-with-dependencies")
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    from(sourceSets.main.get().output)
    dependsOn(configurations.runtimeClasspath)
    from({
        configurations.runtimeClasspath.get().filter { it.name.endsWith(".jar") }.map { zipTree(it) }
    })
    manifest {
        attributes(mapOf("Main-Class" to "demo.JarInstrumenter"))
    }
}

// Make 'build' produce fat JAR as well
tasks.build {
    dependsOn(fatJar)
}
