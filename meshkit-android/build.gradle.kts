plugins {
    kotlin("jvm") version "2.2.20" apply false
    kotlin("plugin.serialization") version "2.2.20" apply false
    // Declared here (not applied) so the Android Gradle Plugin and the Kotlin Android plugin
    // load in the same classloader as the Kotlin plugin above; otherwise kotlin("android")
    // in a subproject cannot see AGP's classes (NoClassDefFoundError: BaseVariant).
    // Versions come from settings.gradle.kts pluginManagement.
    id("com.android.library") apply false
    kotlin("android") apply false
}
