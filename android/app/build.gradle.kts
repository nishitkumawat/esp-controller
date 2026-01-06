import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

/* ------------------ LOAD LOCAL PROPERTIES ------------------ */

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

val flutterVersionCode =
    localProperties.getProperty("flutter.versionCode")?.toInt() ?: 1

val flutterVersionName =
    localProperties.getProperty("flutter.versionName") ?: "1.0"

/* ------------------ LOAD KEYSTORE PROPERTIES ------------------ */

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/* ------------------ ANDROID CONFIG ------------------ */

android {
    namespace = "com.machmate.controller"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.machmate.controller"

        minSdk = flutter.minSdkVersion
        targetSdk = 35

        versionCode = flutterVersionCode
        versionName = flutterVersionName
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }

        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        resources.excludes.add("META-INF/LICENSE*")
        resources.excludes.add("META-INF/NOTICE*")
    }

    bundle {
        abi {
            enableSplit = false
        }
    }

    aaptOptions {
        noCompress("icudtl.dat")
        noCompress("flutter_assets")
    }
}

/* ------------------ FLUTTER CONFIG ------------------ */

flutter {
    source = "../.."
}
