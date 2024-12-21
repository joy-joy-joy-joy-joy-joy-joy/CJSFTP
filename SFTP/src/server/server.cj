package sftp.server

import sftp.packet.SftpPacket
import sftp.constants.*
import std.io.*
import std.collection.*
import encoding.base64.{fromBase64String, toBase64String}
import sftp.version.*
import std.fs.*
import std.sync.*
import std.socket.*
import std.time.*
import sftp.utils.*

public class SftpServer {
    private var handles: HashMap<String, File>
    private let mutex: ReentrantMutex
    private var serverPort: UInt16
    private var running: AtomicBool = AtomicBool(false)  // 使用AtomicBool
    private var serverSocket: Option<TcpServerSocket> = None
    private var connectionCount: AtomicInt32 = AtomicInt32(0)  // 使用AtomicInt32
    private var versionManager: VersionManager = VersionManager()
    
    public init(port: UInt16) {
        this.handles = HashMap<String, File>()
        this.mutex = ReentrantMutex()
        this.serverPort = port
    }

    public func start() {
        running.store(true)
        
        try (serverSocket = TcpServerSocket(bindAt: serverPort)) {
            serverSocket.bind()
            serverPort = serverSocket.localAddress.port
            println("SFTP server listening on port " + serverPort.toString())

            while (running.load()) {
                try (client = serverSocket.accept()) {
                    println("New client connected")
                    // 直接在当前线程处理客户端，而不是创建新线程
                    handleClient(client)
                }
            }
        } catch (e: Exception) {
            running.store(false)
            println("Server error: " + e.message)
        }
    }

    public func stop() {
        running.store(false)
        
        match (serverSocket) {
            case Some(socket) => try {
                socket.close()
                // 等待所有活动连接处理完成
                while (connectionCount.load() > 0) {
                    sleep(Duration.millisecond * 100)
                }
                serverSocket = None
            } catch (e: SocketException) {
                println("Error stopping server: " + e.message)
            }
            case None => ()
        }
    }

    public func getPort(): UInt16 {
        match (serverSocket) {
            case Some(socket) => socket.localAddress.port
            case None => serverPort
        }
    }

    private func handleClient(client: TcpSocket) {
        connectionCount.store(connectionCount.load() + 1)
        println("客户端连接数: " + connectionCount.load().toString())
        
        try {
            client.readTimeout = Some(Duration.second * 5)
            client.writeTimeout = Some(Duration.second * 5)
            let headerBuf = Array<Byte>(9, item: 0)
            
            while (running.load()) {
                // 读取数据包头部
                var totalRead = 0
                while (totalRead < 9) {
                    let count = client.read(headerBuf[totalRead..])
                    if (count <= 0) {
                        return
                    }
                    totalRead += count
                }
                
                // 解析数据包长度
                let length = (UInt32(headerBuf[0]) << 24) |
                            (UInt32(headerBuf[1]) << 16) |
                            (UInt32(headerBuf[2]) << 8) |
                            UInt32(headerBuf[3])
                
                // 读取完整数据包
                let fullPacket = Array<Byte>(Int64(length + 4), item: 0)
                for (i in 0..9) {
                    fullPacket[i] = headerBuf[i]
                }
                
                totalRead = 9
                while (totalRead < Int64(length + 4)) {
                    let count = client.read(fullPacket[totalRead..])
                    if (count <= 0) {
                        return
                    }
                    totalRead += count
                }
                
                // 解码并处理数据包
                match (SftpPacket.decode(fullPacket)) {
                    case Some(packet) => try {
                        match (handlePacket(packet)) {
                            case Some(response) => try {
                                client.write(response.encode())
                                client.flush()
                            } catch (_) {
                                return
                            }
                            case None => ()
                        }
                    } catch (_) {
                        return
                    }
                    case None => println("数据包解码失败")
                }
            }
        } catch (_) {
            // 处理异常
        } finally {
            connectionCount.store(connectionCount.load() - 1)
        }
    }

    private func handlePacket(packet: SftpPacket): Option<SftpPacket> {
        try {
            match (packet.type_) {
                case 1u8 => try {
                    let clientVersion = (UInt32(packet.data[0]) << 24) |
                                    (UInt32(packet.data[1]) << 16) |
                                    (UInt32(packet.data[2]) << 8) |
                                    UInt32(packet.data[3])
                    
                    let negotiatedVersion = versionManager.negotiateVersion(clientVersion)
                    let versionData = [
                        UInt8((negotiatedVersion >> 24) & 0xFF),
                        UInt8((negotiatedVersion >> 16) & 0xFF),
                        UInt8((negotiatedVersion >> 8) & 0xFF),
                        UInt8(negotiatedVersion & 0xFF)
                    ]
                    
                    Some(SftpPacket(2u8, packet.requestId, versionData))
                } catch (e: Exception) {
                    println("处理 INIT 包时出错: " + e.message)
                    None
                }
                case 3u8 => handleOpen(packet)  // 使用已实现的handleOpen
                case 5u8 => handleRead(packet)  // 使用已实现的handleRead
                case _ => try {
                    println("未知的请求类型: " + packet.type_.toString())
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [4u8, 0u8, 0u8, 0u8]))
                } catch (e: Exception) {
                    println("处理未知请求类型时出错: " + e.message)
                    None
                }
            }
        } catch (e: Exception) {
            println("处理数据包时出错: " + e.message)
            None
        }
    }

    public func isRunning(): Bool {
        running.load()
    }

    public func forceShutdown() {
        running.store(false)
        
        match (serverSocket) {
            case Some(socket) => try {
                socket.close()
                // 不等待连接处理完成,直接关闭所有文件句柄
                synchronized(mutex) {
                    for (handle in handles.keys()) {  // 使用 keys() 方法遍历
                        try {
                            handles.get(handle).getOrThrow().close()  // 使用 get 和 getOrThrow 获取值
                        } catch (_) {}
                    }
                    handles.clear()
                }
                serverSocket = None
            } catch (_) {}
            case None => ()
        }
    }

    // 修改 addHandle 方法添加同步
    public func addHandle(handle: String, file: File) {
        synchronized(mutex) {
            handles.put(handle, file)
        }
    }

    // 修改 removeHandle 方法添加同步 
    public func removeHandle(handle: String) {
        synchronized(mutex) {
            handles.remove(handle)
        }
    }

    // 辅助函数：从字节数组中读取 UInt32
    private func readUInt32(data: Array<UInt8>, offset: Int64): UInt32 {
        (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
    }

    // 辅助函数：从字节数组中读取 UInt64
    private func readUInt64(data: Array<UInt8>, offset: Int64): UInt64 {
        (UInt64(data[offset]) << 56) |
        (UInt64(data[offset + 1]) << 48) |
        (UInt64(data[offset + 2]) << 40) |
        (UInt64(data[offset + 3]) << 32) |
        (UInt64(data[offset + 4]) << 24) |
        (UInt64(data[offset + 5]) << 16) |
        (UInt64(data[offset + 6]) << 8) |
        UInt64(data[offset + 7])
    }

    // 辅助函数：从字节数组中读取指定长度的字节
    private func readBytes(data: Array<UInt8>, offset: Int64): Array<UInt8> {
        let length = readUInt32(data, offset)
        let start = offset + Int64(4)
        let end = start + Int64(length)
        data[start..end]
    }

    public func handleOpen(packet: SftpPacket): Option<SftpPacket> {
        try {
            let handle = "handle-" + packet.requestId.toString()
            println("Server received open request for handle: " + handle)
            
            println("Raw packet data: " + SftpPacket.bytesToHex(packet.data))
            println("Packet data size: " + packet.data.size.toString())
            
            let pathLength = readUInt32(packet.data, 0)
            println("Path length from packet: " + pathLength.toString())
            
            let path = readString(packet.data, 0)
            println("Path read: " + path)
            
            let flags = readUInt32(packet.data, Int64(path.size + 4))
            println("With flags: " + flags.toString())
            
            try {
                // 直接以读写模式打开文件
                let file = File(path, OpenOption.CreateOrTruncate(true))
                println("File created")
                
                // 检查文件权限
                if (!file.canRead()) {
                    println("File is not readable")
                    return Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [4u8, 0u8, 0u8, 0u8]))
                }
                
                if (!file.canWrite()) {
                    println("File is not writable")
                    return Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [4u8, 0u8, 0u8, 0u8]))
                }
                
                println("File has read/write permissions")
                
                synchronized(mutex) {
                    handles.put(handle, file)
                }
                
                // 返回句柄
                let handleBytes = handle.toArray()
                let handleLenBytes = [
                    UInt8((handleBytes.size >> 24) & 0xFF),
                    UInt8((handleBytes.size >> 16) & 0xFF),
                    UInt8((handleBytes.size >> 8) & 0xFF),
                    UInt8(handleBytes.size & 0xFF)
                ]
                
                let responseData = Array<UInt8>(handleLenBytes.size + handleBytes.size, item: 0)
                for (i in 0..handleLenBytes.size) {
                    responseData[i] = handleLenBytes[i]
                }
                for (i in 0..handleBytes.size) {
                    responseData[handleLenBytes.size + i] = handleBytes[i]
                }
                
                println("Sending handle response")
                Some(SftpPacket(PacketTypes.FXP_HANDLE, packet.requestId, responseData))
            } catch (e: FSException) {
                println("Failed to open file: " + e.message)
                Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [4u8, 0u8, 0u8, 0u8]))
            }
        } catch (e: Exception) {
            println("Open failed with error: " + e.message)
            Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [4u8, 0u8, 0u8, 0u8]))
        }
    }

    public func handleClose(packet: SftpPacket): Option<SftpPacket> {
        let handle = readString(packet.data, 0)
        
        synchronized(mutex) {
            match (handles.get(handle)) {
                case Some(file) => try {
                    file.close()
                    handles.remove(handle)
                    // 返回成功状态(0)
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [0u8, 0u8, 0u8, 0u8]))
                } catch (e: FSException) {
                    println("Close failed: " + e.message)
                    // 返回失败状态(1)
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                }
                case None => try {
                    println("Handle not found: " + handle)
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                } catch (e: FSException) {
                    println("Error in None branch: " + e.message)
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                }
            }
        }
    }

    public func handleRead(packet: SftpPacket): Option<SftpPacket> {
        let handle = readString(packet.data, 0)
        println("Server received handle: " + handle)
        
        let offset = readUInt64(packet.data, Int64(handle.size + 4))
        println("Server received offset: " + offset.toString())
        
        let length = readUInt32(packet.data, Int64(handle.size + 12))
        println("Server received length to read: " + length.toString())
        
        synchronized(mutex) {
            match (handles.get(handle)) {
                case Some(file) => try {
                    println("Found handle in map")
                    let buffer = Array<UInt8>(Int64(length), item: 0)
                    
                    if (file is Seekable) {
                        println("File is seekable")
                        let seekable = (file as Seekable).getOrThrow()
                        seekable.seek(SeekPosition.Begin(Int64(offset)))
                        println("Seek successful")
                    }
                    
                    let bytesRead = file.read(buffer)
                    println("Bytes read: " + bytesRead.toString())
                    
                    if (bytesRead > 0) {
                        // 直接返回读取的数据，不需要添加长度前缀
                        Some(SftpPacket(PacketTypes.FXP_DATA, packet.requestId, buffer[0..bytesRead]))
                    } else {
                        println("No data read")
                        Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                    }
                } catch (e: FSException) {
                    println("Read failed with FSException: " + e.message)
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                } catch (_) {
                    println("Read failed with unknown exception")
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                }
                case None => println("Handle not found")
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
            }
        }
    }

    public func handleWrite(packet: SftpPacket): Option<SftpPacket> {
        let handle = readString(packet.data, 0)
        println("Server received handle: " + handle)
        
        let offset = readUInt64(packet.data, Int64(handle.size + 4))
        println("Server received offset: " + offset.toString())
        
        let data = readBytes(packet.data, Int64(handle.size + 12))
        println("Server received data size: " + data.size.toString())
        
        match (handles.get(handle)) {
            case Some(file) => try {
                println("Found handle in map")
                
                let future = spawn {
                    if (file is Seekable) {
                        println("File is seekable")
                        let seekable = (file as Seekable).getOrThrow()
                        seekable.seek(SeekPosition.Begin(Int64(offset)))
                        println("Seek successful")
                    }
                    
                    file.write(data)
                    println("Write successful")
                    true
                }
                
                let writeSuccess = future.get()
                if (writeSuccess) {
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [0u8, 0u8, 0u8, 0u8]))
                } else {
                    Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
                }
                
            } catch (e: FSException) {
                println("Write failed: " + e.message)
                Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
            }
            case None => println("Handle not found")
                Some(SftpPacket(PacketTypes.FXP_STATUS, packet.requestId, [1u8, 0u8, 0u8, 0u8]))
        }
    }

}