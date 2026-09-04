import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties on a dev machine or
// from environment variables on CI; without either, release falls back to
// the debug key so any contributor can still build.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun signingValue(propertyName: String, envName: String): String? =
    keystoreProperties.getProperty(propertyName) ?: System.getenv(envName)

val releaseStorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")

// A reproducible build leaves the release APK unsigned so a verifier can
// compare it with the published one and ignore the signature; see
// docs/REPRODUCIBLE-BUILDS.md. Passed as -Pgerfaut.unsigned=true.
val unsignedRelease = (project.findProperty("gerfaut.unsigned") as String?).toBoolean()

android {
    namespace = "com.gerfautwallet.gerfaut"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // The notifications plugin needs the desugared java.time APIs.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.gerfautwallet.gerfaut"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStorePath != null) {
            create("release") {
                storeFile = file(releaseStorePath)
                storePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                unsignedRelease -> null
                releaseStorePath != null -> signingConfigs.getByName("release")
                else -> signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
