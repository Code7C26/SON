import java.util.Properties
import java.io.FileInputStream

// Clave de publicación para las tiendas. android/key.properties y el .jks NO se suben a git.
val propiedadesClave = Properties()
val archivoClave = rootProject.file("key.properties")
if (archivoClave.exists()) {
    propiedadesClave.load(FileInputStream(archivoClave))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sonoperation.tecnico"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identificador definitivo en Google Play: no se puede cambiar después de publicar.
        applicationId = "com.sonoperation.tecnico"
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

    signingConfigs {
        create("release") {
            if (archivoClave.exists()) {
                keyAlias = propiedadesClave["keyAlias"] as String
                keyPassword = propiedadesClave["keyPassword"] as String
                storeFile = file(propiedadesClave["storeFile"] as String)
                storePassword = propiedadesClave["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Con android/key.properties firma con la clave de publicación; sin ella, con la de
            // prueba (sirve para probar, pero las tiendas la rechazan).
            signingConfig = if (archivoClave.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
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
