// src/test/server_test.cj
package sftp.test

import sftp.packet.SftpPacket
import sftp.constants.PacketTypes
import sftp.server.SftpServer
import std.fs.*
import std.collection.HashMap
import std.io.*
import std.socket.*
import std.time.*
import std.sync.sleep

@Test
class ServerTest {
    private var serverPort: UInt16 = 8000
    private var server: SftpServer = SftpServer(serverPort)
    private var testFile: Option<File> = None
    private let testPath = "test.txt"
    private let testHandle = "test-handle"
    private var serverFuture: Option<Future<Unit>> = None

    @BeforeEach
    func setup() {
        println("开始设置测试环境...")
        // 启动服务器
        serverFuture = spawn {
            server.start()
        }
        
        // 创建测试文件
        try (file = File(testPath, OpenOption.CreateOrTruncate(true))) {
            testFile = Some(file)
            // 在添加 handle 之前先关闭并重新打开文件以确保可写和可定位
            file.close()
            let reopenedFile = File(testPath, OpenOption.Open(true, true))  // 读写模式打开
            testFile = Some(reopenedFile)
            server.addHandle(testHandle, reopenedFile)
        } catch (e: FSException) {
            println("Failed to create test file: " + e.message)
            @Fail("Failed to create test file")
        }
    }

    @AfterEach
    func teardown() {
        // 关闭测试文件
        match (testFile) {
            case Some(file) => try {
                file.close()
            } catch (e: FSException) {
                println("Failed to close test file: " + e.message)
            }
            case None => ()
        }
        
        // 删除测试文件
        try {
            File.delete(testPath)
        } catch (e: FSException) {
            println("Failed to delete test file: " + e.message)
        }
        
        // 停止服务器
        server.stop()
        
        // 等待服务器线程结束
        match (serverFuture) {
            case Some(future) => future.get()
            case None => ()
        }
    }

    @TestCase
    func testRead() {
        let writeData = "Hello World".toArray()

        // 先写入一些测试数据并重新打开文件
        try (file = testFile.getOrThrow()) {
            file.write(writeData)
            file.close()
            let reopenedFile = File(testPath, OpenOption.Open(true, true))
            testFile = Some(reopenedFile)
            server.addHandle(testHandle, reopenedFile)
        } catch (e: FSException) {
            println("Failed to write test data: " + e.message)
            @Fail("Failed to write test data")
        }

        let numThreads = 5
        var futures = Array<Option<SftpPacket>>(numThreads + 1, item: None)  // 创建固定大小的数组,用 None 初始化

        // 创建并发读取请求
        for (i in 0..numThreads) {  // 0 到 numThreads-1
            let totalSize = 4 + testHandle.size + 8 + 4
            var packetData = Array<UInt8>(totalSize, item: 0u8)
            var pos = 0

            // 1. handle length (4 bytes)
            let handleLength = UInt32(testHandle.size)
            packetData[0] = UInt8((handleLength >> 24) & 0xFF)
            packetData[1] = UInt8((handleLength >> 16) & 0xFF)
            packetData[2] = UInt8((handleLength >> 8) & 0xFF)
            packetData[3] = UInt8(handleLength & 0xFF)
            pos = 4

            // 2. handle content
            let handleBytes = testHandle.toArray()
            for (j in 0..handleBytes.size) {
                packetData[pos + j] = handleBytes[j]
            }
            pos = pos + handleBytes.size

            // 3. offset (8 bytes)
            let offset = UInt64(i * 2)
            packetData[pos] = UInt8((offset >> 56) & 0xFF)
            packetData[pos + 1] = UInt8((offset >> 48) & 0xFF)
            packetData[pos + 2] = UInt8((offset >> 40) & 0xFF)
            packetData[pos + 3] = UInt8((offset >> 32) & 0xFF)
            packetData[pos + 4] = UInt8((offset >> 24) & 0xFF)
            packetData[pos + 5] = UInt8((offset >> 16) & 0xFF)
            packetData[pos + 6] = UInt8((offset >> 8) & 0xFF)
            packetData[pos + 7] = UInt8(offset & 0xFF)
            pos = pos + 8

            // 4. length to read (4 bytes)
            let readLength = UInt32(2)
            packetData[pos] = UInt8((readLength >> 24) & 0xFF)
            packetData[pos + 1] = UInt8((readLength >> 16) & 0xFF)
            packetData[pos + 2] = UInt8((readLength >> 8) & 0xFF)
            packetData[pos + 3] = UInt8(readLength & 0xFF)

            let readPacket = SftpPacket(PacketTypes.FXP_READ, UInt32(i), packetData)
            let future = spawn {
                server.handleRead(readPacket)
            }
            futures[i] = future.get()
        }

        // 验证结果
        for (i in 0..numThreads) {  // 0 到 numThreads-1
            match (futures.get(i)) {
                case Some(optPacket) => match (optPacket) {
                    case Some(packet) => println("Thread " + i.toString() + " response type: " + packet.type_.toString())
                        println("Thread " + i.toString() + " data size: " + packet.data.size.toString())
                        @Assert(packet.type_ == PacketTypes.FXP_DATA)
                        let expectedData = writeData[i * 2..(i * 2 + 2)]
                        @Assert(packet.data == expectedData)
                    case None => @Fail("Packet is None for thread " + i.toString())
                }
                case None => @Fail("Future result is None for thread " + i.toString())
            }
        }
    }
    
    @TestCase
    func testConcurrentRead() {
        // 准备测试数据
        let testData = "Hello World!"
        let writeData = testData.toArray()
        
        // 写入测试文件
        try (file = testFile.getOrThrow()) {
            file.write(writeData)
            file.close()
            let reopenedFile = File(testPath, OpenOption.Open(true, true))
            testFile = Some(reopenedFile)
            server.addHandle(testHandle, reopenedFile)
        } catch (e: FSException) {
            println("Failed to write test data: " + e.message)
            @Fail("Failed to write test data")
        }

        // 创建多个并发读取请求
        let numThreads = 4  // 4个并发线程
        let readSize = 3    // 每次读取3个字节
        var futures = Array<Option<SftpPacket>>(numThreads, item: None)

        // 发起并发读取
        for (i in 0..numThreads) {
            let offset = i * readSize  // 每个线程读取不同位置
            
            // 构造读取请求包
            let totalSize = 4 + testHandle.size + 8 + 4  // handle长度 + handle + offset + length
            var packetData = Array<UInt8>(totalSize, item: 0u8)
            var pos = 0

            // 写入handle长度
            let handleLength = UInt32(testHandle.size)
            packetData[0] = UInt8((handleLength >> 24) & 0xFF)
            packetData[1] = UInt8((handleLength >> 16) & 0xFF)
            packetData[2] = UInt8((handleLength >> 8) & 0xFF)
            packetData[3] = UInt8(handleLength & 0xFF)
            pos = 4

            // 写入handle
            let handleBytes = testHandle.toArray()
            for (j in 0..handleBytes.size) {
                packetData[pos + j] = handleBytes[j]
            }
            pos = pos + handleBytes.size

            // 写入offset
            let offsetUint = UInt64(offset)
            packetData[pos] = UInt8((offsetUint >> 56) & 0xFF)
            packetData[pos + 1] = UInt8((offsetUint >> 48) & 0xFF)
            packetData[pos + 2] = UInt8((offsetUint >> 40) & 0xFF)
            packetData[pos + 3] = UInt8((offsetUint >> 32) & 0xFF)
            packetData[pos + 4] = UInt8((offsetUint >> 24) & 0xFF)
            packetData[pos + 5] = UInt8((offsetUint >> 16) & 0xFF)
            packetData[pos + 6] = UInt8((offsetUint >> 8) & 0xFF)
            packetData[pos + 7] = UInt8(offsetUint & 0xFF)
            pos = pos + 8

            // 写入读取长度
            let readLength = UInt32(readSize)
            packetData[pos] = UInt8((readLength >> 24) & 0xFF)
            packetData[pos + 1] = UInt8((readLength >> 16) & 0xFF)
            packetData[pos + 2] = UInt8((readLength >> 8) & 0xFF)
            packetData[pos + 3] = UInt8(readLength & 0xFF)

            // 发送请求并保存future
            let readPacket = SftpPacket(PacketTypes.FXP_READ, UInt32(i), packetData)
            let future = spawn { server.handleRead(readPacket) }
            futures[i] = future.get()
        }

        // 验证结果
        for (i in 0..numThreads) {
            match (futures.get(i)) {
                case Some(optPacket) => match (optPacket) {
                    case Some(packet) => try {
                        let start = i * readSize
                        let end = if (start + readSize > writeData.size) {
                            writeData.size
                        } else {
                            start + readSize
                        }
                        let expectedData = writeData[start..end]
                        
                        println("Thread " + i.toString() + " response type: " + packet.type_.toString())
                        println("Expected: " + String.fromUtf8(expectedData))
                        println("Got: " + String.fromUtf8(packet.data))
                        
                        @Assert(packet.type_ == PacketTypes.FXP_DATA)
                        @Assert(packet.data == expectedData)
                    } catch (e: SpawnException) {
                        @Fail("Thread " + i.toString() + " failed: " + e.message)
                    }
                    case None => @Fail("Packet is None for thread " + i.toString())
                }
                case None => @Fail("Future result is None for thread " + i.toString())
            }
        }
    }

   @TestCase
    public func testConcurrentRequests() {
        let server = SftpServer(8000u16)
        
        let serverFuture = spawn {
            try {
                server.start()
            } catch (e: Exception) {
                println("服务器异常: " + e.message)
            }
        }
        
        // 等待服务器启动
        sleep(Duration.second * 1)
        
        try (socket = TcpSocket("127.0.0.1", server.getPort())) {
            socket.readTimeout = Some(Duration.second * 5)
            socket.writeTimeout = Some(Duration.second * 5)
            socket.connect(timeout: Duration.second * 5)
            println("Client connected")
            
            // 发送多个请求包
            let numRequests = 5
            for (i in 0..numRequests) {
                // 发送 INIT 包
                let initPacket = SftpPacket(1u8, UInt32(i), [0u8, 0u8, 0u8, 3u8])
                let encodedData = initPacket.encode()
                println("发送请求 ${i}, 数据内容: " + SftpPacket.bytesToHex(encodedData))
                socket.write(encodedData)
                socket.flush()
                
                // 等待服务器处理
                sleep(Duration.millisecond * 100)
                
                // 读取响应
                let headerBuf = Array<Byte>(9, item: 0)
                var totalRead = 0
                while (totalRead < 9) {
                    let count = socket.read(headerBuf[totalRead..])
                    if (count <= 0) {
                        throw Exception("读取响应头部失败")
                    }
                    totalRead += count
                }
                
                println("收到响应头部: " + SftpPacket.bytesToHex(headerBuf[0..9]))
                
                // 解析长度
                let length = (UInt32(headerBuf[0]) << 24) |
                            (UInt32(headerBuf[1]) << 16) |
                            (UInt32(headerBuf[2]) << 8) |
                            UInt32(headerBuf[3])
                
                println("响应包长度: " + length.toString())
                
                // 读取完整响应
                let fullPacket = Array<Byte>(Int64(length + 4), item: 0)
                for (j in 0..9) {
                    fullPacket[j] = headerBuf[j]
                }
                
                totalRead = 9
                while (totalRead < Int64(length + 4)) {
                    let count = socket.read(fullPacket[totalRead..])
                    if (count <= 0) {
                        throw Exception("读取响应数据失败")
                    }
                    totalRead += count
                }
                
                println("完整响应数据: " + SftpPacket.bytesToHex(fullPacket))
                
                // 验证响应
                match (SftpPacket.decode(fullPacket)) {
                    case Some(response) => try {
                        if (response.type_ != 2u8) {
                            throw Exception("期望 FXP_VERSION 响应")
                        }
                        if (response.requestId != UInt32(i)) {
                            throw Exception("请求ID不匹配")
                        }
                        if (response.data != [0u8, 0u8, 0u8, 3u8]) {
                            throw Exception("版本号不匹配")
                        }
                        println("请求 ${i} 验证通过")
                    } catch (e: Exception) {
                        println("验证失败: " + e.message)
                        throw e
                    }
                    case None => throw Exception("响应包解码失败")
                }
                
                // 等待一下再发送下一个请求
                sleep(Duration.millisecond * 100)
            }
        } catch (e: Exception) {
            println("测试失败: " + e.message)
            throw e
        } finally {
            println("正在关闭服务器...")
            server.stop()
            println("服务器已关闭")
        }
        
        println("并发请求测试通过!")
    }

}