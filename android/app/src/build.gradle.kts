import java.util.Properties
import java.io.FileInputStream

// 1. قراءة ملف key.properties بصيغة Kotlin
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // الهوية الخاصة بتطبيق راحة
    namespace = "com.ibrahim.raha_hr" 
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" 

    // 2. إعدادات التوقيع (Signing Configs)
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    compileOptions {
        // --- تعديل هنا لحل مشكلة الإشعارات ---
        isCoreLibraryDesugaringEnabled = true 
        
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.ibrahim.raha_hr" 
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = 2 
        versionName = "1.0.1"
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// --- إضافة هذا القسم في نهاية الملف تماماً ---
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
