plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pharos.pharos_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Java 17 matches the JDK bundled with Android Studio / Flutter toolchain.
        // Do NOT raise this to 21 — the bundled JDK does not support it.
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // KGP 2.x uses compilerOptions instead of the deprecated kotlinOptions block.
    kotlin {
        compilerOptions {
            jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }
    }

    defaultConfig {
        applicationId = "com.pharos.pharos_flutter"
        // LiteRT-LM requires API 26+ (Android 8.0) for GPU delegate & NNAPI.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LiteRT-LM — on standard Google Maven, no custom repo needed.
    // 0.11.0 is the version Google AI Edge Gallery currently ships with and
    // the litert-community HuggingFace models are built for.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.11.0")

    // Kotlin coroutines for background inference work
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
