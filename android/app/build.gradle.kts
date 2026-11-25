plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

@CacheableTask
abstract class GenerateSaepPolicy : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val template: RegularFileProperty

    @get:Input
    abstract val applicationId: Property<String>

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val source = template.get().asFile.readText()
        val placeholder = "\${applicationId}"
        check(placeholder in source) { "SAEP policy template is missing the applicationId placeholder" }
        val resource = outputDirectory.file("raw/agent_saep_policy.json").get().asFile
        resource.parentFile.mkdirs()
        resource.writeText(source.replace(placeholder, applicationId.get()))
    }
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

    // 签名密钥不进仓库：通过环境变量提供（CI 里由 GitHub Actions secrets 注入）。
    //   TESLA_KS_PATH        keystore 文件路径
    //   TESLA_KS_PASSWORD    keystore 密码
    //   TESLA_KEY_ALIAS      密钥别名
    //   TESLA_KEY_PASSWORD   密钥密码
    // 未提供时 release 保持未签名（CI 会跳过发布），本地仍可构建 debug 包。
    val signingKeystore = System.getenv("TESLA_KS_PATH")
        ?.let { file(it) }
        ?.takeIf { it.exists() }
    signingConfigs {
        if (signingKeystore != null) {
            create("release") {
                storeFile = signingKeystore
                storePassword = System.getenv("TESLA_KS_PASSWORD")
                keyAlias = System.getenv("TESLA_KEY_ALIAS")
                keyPassword = System.getenv("TESLA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (signingKeystore != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        debug {
            applicationIdSuffix = ".debug"
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

androidComponents {
    onVariants { variant ->
        val generate = tasks.register<GenerateSaepPolicy>("generate${variant.name.replaceFirstChar { it.uppercaseChar() }}SaepPolicy") {
            template.set(layout.projectDirectory.file("src/main/saep/agent_saep_policy.json"))
            applicationId.set(variant.applicationId)
            outputDirectory.set(layout.buildDirectory.dir("generated/saep/${variant.name}/res"))
        }
        variant.sources.res?.addGeneratedSourceDirectory(generate, GenerateSaepPolicy::outputDirectory)
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
