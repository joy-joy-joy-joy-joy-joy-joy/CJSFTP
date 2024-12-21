package sftp

import sftp.packet.SftpPacket
import sftp.server.SftpServer
import std.socket.*
import std.time.*
import std.fs.*
import std.sync.sleep
import sftp.utils.*
import sftp.constants.*

main() : Unit {
    println("=== 开始 SFTP 测试 ===")

    // 在 main() 函数中添加
    let testData = [
        0x00u8, 0x00u8, 0x00u8, 0x08u8,  // 长度为 8
        0x74u8, 0x65u8, 0x73u8, 0x74u8, 0x2Eu8, 0x74u8, 0x78u8, 0x74u8, // "test.txt"
        0x00u8, 0x00u8, 0x00u8, 0x01u8, 0x00u8, 0x00u8, 0x00u8, 0x00u8  // 其他数据
    ]
    println("测试 readString:")
    let str = readString(testData, 0)
    println("读取的字符串: " + str)
    
    let server = SftpServer(8000u16)

    // 启动服务器
    let serverFuture = spawn {
        try {
            server.start()
        } catch (e: Exception) {
            println("服务器异常: " + e.message)
        }
    }
    
    sleep(Duration.second * 1)
    
    try {
        let client = TcpSocket("127.0.0.1", 8000u16)
        client.readTimeout = Some(Duration.second * 5)
        client.writeTimeout = Some(Duration.second * 5)
        client.connect(timeout: Duration.second * 5)
        
        // 1. 版本协商
        let initPacket = SftpPacket.makeInit(1u32, 3u32)
        client.write(initPacket.encode())
        client.flush()
        println("发送版本协商包")
        
        // 读取响应
        let versionResponse = readAndDecodePacket(client)
        println("版本协商响应类型: " + versionResponse.type_.toString())
        
        //2. 打开文件
        let openPacket = SftpPacket.makeOpen(2u32, "test.txt", 1u32, 0u32)
        client.write(openPacket.encode())
        client.flush()
        println("发送打开文件请求")
        
        let openResponse = readAndDecodePacket(client)
        println("打开文件响应类型: " + openResponse.type_.toString())
        
        // 3. 读取文件
        // 测试 makeRead 函数的数据构造
        let handle = "handle-2"
        let readPacket = SftpPacket.makeRead(3u32, handle, 0u64, 1024u32)

        // 在发送读取请求后添加等待
        println("发送读取请求...")
        client.write(readPacket.encode())
        client.flush()

        let readResponse = readAndDecodePacket(client)
        println("读取响应类型: " + readResponse.type_.toString())
        println("读取响应数据: " + SftpPacket.bytesToHex(readResponse.data))

        // 如果是数据响应，尝试解析数据内容
        if (readResponse.type_ == PacketTypes.FXP_DATA) {
            let data = String.fromUtf8(readResponse.data)
            println("读取到的文件内容: " + data)
        } else {
            println("收到错误响应")
        }
        
        client.close()
    } catch (e: Exception) {
        println("测试失败: " + e.message)
    }
    
    server.stop()
}

private func readAndDecodePacket(client: TcpSocket): SftpPacket {
    println("开始读取响应头部...")
    let headerBuf = Array<Byte>(9, item: 0)
    var totalRead = 0
    
    while (totalRead < 9) {
        println("尝试读取头部，当前已读取: " + totalRead.toString() + " 字节")
        let count = client.read(headerBuf[totalRead..])
        println("本次读取返回值: " + count.toString())
        if (count <= 0) {
            throw Exception("读取响应头部失败，返回值: " + count.toString())
        }
        totalRead += count
        println("当前头部数据: " + SftpPacket.bytesToHex(headerBuf[0..totalRead]))
    }
    
    println("头部读取完成，完整头部: " + SftpPacket.bytesToHex(headerBuf))
    
    let length = (UInt32(headerBuf[0]) << 24) |
                 (UInt32(headerBuf[1]) << 16) |
                 (UInt32(headerBuf[2]) << 8) |
                 UInt32(headerBuf[3])
                 
    println("解析的数据包长度: " + length.toString())
    
    let fullPacket = Array<Byte>(Int64(length + 4), item: 0)
    for (i in 0..9) {
        fullPacket[i] = headerBuf[i]
    }
    
    println("开始读取数据部分...")
    totalRead = 9
    while (totalRead < Int64(length + 4)) {
        println("尝试读取数据，当前进度: " + totalRead.toString() + "/" + (length + 4).toString())
        let count = client.read(fullPacket[totalRead..])
        println("本次读取返回值: " + count.toString())
        if (count <= 0) {
            throw Exception("读取响应数据失败，返回值: " + count.toString())
        }
        totalRead += count
        println("当前已读取数据: " + SftpPacket.bytesToHex(fullPacket[0..totalRead]))
    }
    
    println("完整数据包: " + SftpPacket.bytesToHex(fullPacket))
    
    match (SftpPacket.decode(fullPacket)) {
        case Some(packet) => try {
            println("数据包解码成功:")
            println("- 类型: " + packet.type_.toString())
            println("- 请求ID: " + packet.requestId.toString())
            println("- 数据长度: " + packet.data.size.toString())
            packet
        } catch (e: Exception) {
            throw Exception("数据包解码后处理失败: " + e.message)
        }
        case None => throw Exception("响应包解码失败")
    }
}