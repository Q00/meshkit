plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    // Golden vectors live at the repo root of meshkit-android.
    systemProperty("meshkit.vectors", rootProject.file("vectors/wire-compat.v1.json").absolutePath)
    // Kotlin-signed envelopes for the Swift cross-verify step
    // (scripts/verify_android_wire_compat.sh).
    systemProperty("meshkit.crosssign.out", rootProject.file("build/kotlin-signed.v1.json").absolutePath)
}
