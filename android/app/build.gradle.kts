plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// CI 通过 BUILD_NUMBER 注入递增的构建号，本地构建时回退到 0。
// versionCode 必须递增，否则手机上覆盖安装会失败。
val buildNumber: Int = (System.getenv("BUILD_NUMBER") ?: "0").toIntOrNull() ?: 0
val appVersionCode: Int = 1 + buildNumber
// 打标签构建时由 CI 传入 VERSION_NAME（如 v1.0.0），其余情况用 1.0.<构建号>
val taggedVersion: String? = System.getenv("VERSION_NAME")
    ?.removePrefix("v")
    ?.takeIf { it.isNotBlank() }
val appVersionName: String = taggedVersion ?: if (buildNumber == 0) "1.0.0" else "1.0.$buildNumber"

android {
    namespace = "com.teslacam.timestamp"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.teslacam.timestamp"
        minSdk = 26
        targetSdk = 34
        versionCode = appVersionCode
        versionName = appVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
    }

    // 仓库内固定签名（CI 与本地一致），保证版本之间可以覆盖安装。
    // 如果改用私有密钥，可用环境变量覆盖：TESLA_KS_PATH / TESLA_KS_PASSWORD / TESLA_KEY_ALIAS / TESLA_KEY_PASSWORD
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("TESLA_KS_PATH") ?: "../keystore/ci.jks")
            storePassword = System.getenv("TESLA_KS_PASSWORD") ?: "tesla-timestamp-ci"
            keyAlias = System.getenv("TESLA_KEY_ALIAS") ?: "teslats"
            keyPassword = System.getenv("TESLA_KEY_PASSWORD") ?: "tesla-timestamp-ci"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            applicationIdSuffix = ".debug"
            // debug 也用同一把 key，方便和正式包来回覆盖安装
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
    }

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES")
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.activity:activity-ktx:1.9.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.4")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.8.4")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.1")
    androidTestImplementation("androidx.test:rules:1.6.1")
    androidTestImplementation("androidx.test:core-ktx:1.6.1")
}
