allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 10.3.3 硬编码 kotlinOptions jvmTarget=1.8，而 Flutter 工具链为插件
// 子项目统一设置 Java 11 → KGP jvm-target 校验失败（compileReleaseKotlin
// "Inconsistent JVM Target Compatibility"）。仅对 :file_picker 把 Kotlin 对齐到
// 11（其 Java 侧已是 11，无需改动）；升级 file_picker 后可移除本块。
subprojects {
    afterEvaluate {
        if (project.name == "file_picker") {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
                .configureEach {
                    compilerOptions.jvmTarget
                        .set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
