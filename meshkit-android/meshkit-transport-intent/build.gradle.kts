plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "ai.meshkit.transport"
    compileSdk = 36

    defaultConfig {
        // Android Keystore Ed25519 (Curve 25519) requires API 33.
        minSdk = 33
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    api(project(":meshkit-core"))
    implementation("androidx.activity:activity-ktx:1.9.3")
}
