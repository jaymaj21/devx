plugins {
    `java`
}

group = "com.trading"
version = "1.0-SNAPSHOT"

tasks.jar {
    archiveBaseName.set("TradingSystem")
}

java {
    toolchain.languageVersion.set(JavaLanguageVersion.of(17))
}

dependencies {
    implementation("org.clojure:clojure:1.11.3")
    testImplementation("org.junit.jupiter:junit-jupiter-api:5.7.1")
    testImplementation("org.junit.jupiter:junit-jupiter-engine:5.7.1")
}

tasks.test {
    useJUnitPlatform()
}

