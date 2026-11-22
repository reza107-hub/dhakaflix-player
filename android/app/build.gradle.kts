plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.dhakaflix.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.dhakaflix.player"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing comes only from environment variables, never from files
    // in this repository. Locally: `. tool/signing.sh`; in CI: GitHub secrets.
    val keystorePath = System.getenv("DFP_KEYSTORE")
    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("DFP_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DFP_KEY_ALIAS")
                keyPassword = System.getenv("DFP_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without signing variables, fall back to debug keys so local test
            // builds still work. Such APKs must not be published.
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("DFP_KEYSTORE not set: release APK is signed with the DEBUG key.")
                signingConfigs.getByName("debug")
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
