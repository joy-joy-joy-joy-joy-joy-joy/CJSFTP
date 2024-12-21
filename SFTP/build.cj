// build.cj

import std.os.*

// build命令执行前的处理
func stagePreBuild(): Int64 {
    println("开始构建SFTP服务器...")
    return 0
}

// build命令执行后的处理
func stagePostBuild(): Int64 {
    println("SFTP服务器构建完成")
    return 0
}

main(): Int64 {
    // 根据命令行参数执行对应的处理函数
    match (getArgs()[0]) {
        case "pre-build" => stagePreBuild()
        case "post-build" => stagePostBuild()
        case _ => 0
    }
}