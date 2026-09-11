rootProject.name = "meshkit-android"

pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
    plugins {
        // Resolved only when an Android module is included (see below).
        id("com.android.library") version "8.7.3"
        id("org.jetbrains.kotlin.android") version "2.2.20"
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

include(":meshkit-core")

// Android library and sample modules need an Android SDK; keep the pure-JVM
// trust layer buildable without one.
val hasAndroidSdk = System.getenv("ANDROID_HOME") != null ||
    System.getenv("ANDROID_SDK_ROOT") != null ||
    file("local.properties").exists()
if (hasAndroidSdk) {
    include(":meshkit-transport-intent")
}
