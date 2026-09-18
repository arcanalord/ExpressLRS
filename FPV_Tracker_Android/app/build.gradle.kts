plugins {
    id("com.android.application")
}

android {
    namespace = "ru.fpvclub.tracker"
    compileSdk = 36

    defaultConfig {
        applicationId = "ru.fpvclub.tracker"
        minSdk = 26
        targetSdk = 36
        versionCode = 3
        versionName = "0.3.0"
    }

    buildTypes { release { isMinifyEnabled = false } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    buildFeatures { viewBinding = true }
}

dependencies {
    val camerax = "1.6.2"
    implementation("androidx.activity:activity-ktx:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.4")
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")
    implementation("org.opencv:opencv:5.0.0.1")
    testImplementation("junit:junit:4.13.2")
}
