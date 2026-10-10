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
// 注意：上方 evaluationDependsOn 会在根脚本配置期提前求值 :app，故此处不能用
// afterEvaluate（"project is already evaluated"）；configureEach 惰性生效，
// 于任务 realization 时覆盖插件写入的 1.8。
subprojects {
    if (project.name == "file_picker") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions.jvmTarget
                    .set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
