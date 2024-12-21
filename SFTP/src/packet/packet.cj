package sftp.packet

import sftp.constants.PacketTypes
import sftp.constants.OpenFlags
import sftp.constants.StatusCodes
import sftp.constants.AttributeFlags
import sftp.utils.*

import std.socket.*
import std.time.*
import std.sync.*

public class SftpPacket{
    public let length: UInt32
    public let type_: UInt8
    public let requestId: UInt32
    public let data: Array<UInt8>

    public init(type_: UInt8, requestId: UInt32, data: Array<UInt8>) {
        this.type_ = type_
        this.requestId = requestId
        this.data = data
        this.length = UInt32(1 + 4 + data.size)
    }

    private static func byteToHex(b: UInt8): String {
        let high = UInt8(b >> 4)
        let low = UInt8(b & 0x0F)
        
        func digitToHex(digit: UInt8): String {
            if (digit < 10) {
                // ASCII '0' = 48
                return String(Rune(UInt32(digit) + 48))
            } else {
                // ASCII 'A' = 65
                return String(Rune(UInt32(digit - 10) + 65))
            }
        }
        
        return digitToHex(high) + digitToHex(low)
    }

    public static func bytesToHex(bytes: Array<UInt8>): String {
        var result = ""
        for (i in 0..bytes.size) {
            if (i > 0) {
                result = result + " "
            }
            result = result + SftpPacket.byteToHex(bytes[i])
        }
        return result
    }

    private static func stringToBytes(str: String): Array<UInt8> {
        var bytes = Array<UInt8>()
        var size = 0
        
        // 先计算需要的字节数
        for (c in str) {
            let rune = UInt32(c)
            if (rune < 0x80) {
                size += 1
            } else if (rune < 0x800) {
                size += 2
            } else if (rune < 0x10000) {
                size += 3
            } else {
                size += 4
            }
        }
        
        // 创建固定大小的数组
        bytes = Array<UInt8>(size, item:0)
        var pos = 0
        
        // 填充数组
        for (c in str) {
            let rune = UInt32(c)
            if (rune < 0x80) {
                bytes[pos] = UInt8(rune)
                pos += 1
            } else if (rune < 0x800) {
                bytes[pos] = UInt8(0xC0 | (rune >> 6))
                bytes[pos + 1] = UInt8(0x80 | (rune & 0x3F))
                pos += 2
            } else if (rune < 0x10000) {
                bytes[pos] = UInt8(0xE0 | (rune >> 12))
                bytes[pos + 1] = UInt8(0x80 | ((rune >> 6) & 0x3F))
                bytes[pos + 2] = UInt8(0x80 | (rune & 0x3F))
                pos += 3
            } else {
                bytes[pos] = UInt8(0xF0 | (rune >> 18))
                bytes[pos + 1] = UInt8(0x80 | ((rune >> 12) & 0x3F))
                bytes[pos + 2] = UInt8(0x80 | ((rune >> 6) & 0x3F))
                bytes[pos + 3] = UInt8(0x80 | (rune & 0x3F))
                pos += 4
            }
        }
        
        return bytes
    }

    private static func uint32ToBytes(value: UInt32): Array<UInt8> {
        var bytes = Array<UInt8>(4, item:0)
        bytes[0] = UInt8((value >> 24) & 0xFF)
        bytes[1] = UInt8((value >> 16) & 0xFF)
        bytes[2] = UInt8((value >> 8) & 0xFF)
        bytes[3] = UInt8(value & 0xFF)
        return bytes
    }

    private static func uint64ToBytes(value: UInt64): Array<UInt8> {
        var bytes = Array<UInt8>(8, item:0)
        bytes[0] = UInt8((value >> 56) & 0xFF)
        bytes[1] = UInt8((value >> 48) & 0xFF)
        bytes[2] = UInt8((value >> 40) & 0xFF)
        bytes[3] = UInt8((value >> 32) & 0xFF)
        bytes[4] = UInt8((value >> 24) & 0xFF)
        bytes[5] = UInt8((value >> 16) & 0xFF)
        bytes[6] = UInt8((value >> 8) & 0xFF)
        bytes[7] = UInt8(value & 0xFF)
        return bytes
    }

    public func encode(): Array<UInt8> {
        // 计算总长度：length(4) + type(1) + requestId(4) + data
        let totalLen = 9 + data.size
        var buf = Array<UInt8>(totalLen, item:0)
        var pos = 0
        
        // 写入长度(4字节,大端序)
        buf[pos] = UInt8((length >> 24) & 0xFF)
        buf[pos + 1] = UInt8((length >> 16) & 0xFF)
        buf[pos + 2] = UInt8((length >> 8) & 0xFF)
        buf[pos + 3] = UInt8(length & 0xFF)
        pos += 4
        
        // 写入类型(1字节)
        buf[pos] = type_
        pos += 1
        
        // 写入请求ID(4字节,大端序)
        buf[pos] = UInt8((requestId >> 24) & 0xFF)
        buf[pos + 1] = UInt8((requestId >> 16) & 0xFF)
        buf[pos + 2] = UInt8((requestId >> 8) & 0xFF)
        buf[pos + 3] = UInt8(requestId & 0xFF)
        pos += 4
        
        // 写入数据
        for (byte in data) {
            buf[pos] = byte
            pos += 1
        }

        println("编码: length=${length}, type=${type_}, requestId=${requestId}, dataSize=${data.size}")
        if (data.size <= 64) {
            println("数据内容: ${bytesToHex(data)}")
            println("编码结果: ${bytesToHex(buf)}")
        } else {
            // 只显示前32字节
            let preview = Array<UInt8>(data[0..32])
            println("数据内容(前32字节): ${bytesToHex(preview)}... (共${data.size}字节)")
            let bufPreview = Array<UInt8>(buf[0..41])  // 头部9字节 + 32字节数据
            println("编码结果(前41字节): ${bytesToHex(bufPreview)}... (共${buf.size}字节)")
        }
        
        return buf
    }

    public static func decode(bytes: Array<UInt8>): ?SftpPacket {
        if (bytes.size < 9) {
            return None
        }

        // 检查长度字段，防止溢出
        let len1 = UInt32(bytes[0])
        let len2 = UInt32(bytes[1])
        let len3 = UInt32(bytes[2])
        let len4 = UInt32(bytes[3])
        
        // 检查是否会发生溢出
        if (len1 > 0x7F) { // 最高位为1表示可能溢出
            return None
        }
        
        let expectedLen = (len1 << 24) |
                         (len2 << 16) |
                         (len3 << 8) |
                         len4
        
        // 检查总长度是否合理
        if (expectedLen > 0x7FFFFFFF) { // 超过最大允许长度
            return None
        }
        
        if (UInt32(bytes.size) < expectedLen + 4) {
            return None
        }

        let type_ = bytes[4]
        let requestId = (UInt32(bytes[5]) << 24) |
                       (UInt32(bytes[6]) << 16) |
                       (UInt32(bytes[7]) << 8) |
                       UInt32(bytes[8])

        let data = Array<UInt8>(bytes[9..])

        println("解码: length=${expectedLen}, type=${type_}, requestId=${requestId}, dataSize=${data.size}")
        if (data.size <= 64) {
            println("数据内容: ${bytesToHex(data)}")
        } else {
            let preview = Array<UInt8>(data[0..32])
            println("数据内容(前32字节): ${bytesToHex(preview)}... (共${data.size}字节)")
        }

        return Some(SftpPacket(type_, requestId, data))
    }

    // 工厂方法

    public static func makeInit(requestId: UInt32, version: UInt32): SftpPacket {
        let versionData = [
            UInt8((version >> 24) & 0xFF),
            UInt8((version >> 16) & 0xFF), 
            UInt8((version >> 8) & 0xFF),
            UInt8(version & 0xFF)
        ]
        return SftpPacket(PacketTypes.FXP_INIT, requestId, versionData)
    }

    public static func makeOpen(requestId: UInt32, path: String, pflags: UInt32, attrs: UInt32): SftpPacket {
        let pathBytes = path.toArray()
        let totalSize = 4 + pathBytes.size + 8  // 长度字段 + 路径 + pflags + attrs
        let data = Array<UInt8>(totalSize, item: 0)
        
        // 写入路径长度
        data[0] = UInt8((pathBytes.size >> 24) & 0xFF)
        data[1] = UInt8((pathBytes.size >> 16) & 0xFF)
        data[2] = UInt8((pathBytes.size >> 8) & 0xFF)
        data[3] = UInt8(pathBytes.size & 0xFF)
        
        // 写入路径
        for (i in 0..pathBytes.size) {
            data[4 + i] = pathBytes[i]
        }
        
        // 写入 pflags
        data[4 + pathBytes.size] = UInt8((pflags >> 24) & 0xFF)
        data[5 + pathBytes.size] = UInt8((pflags >> 16) & 0xFF)
        data[6 + pathBytes.size] = UInt8((pflags >> 8) & 0xFF)
        data[7 + pathBytes.size] = UInt8(pflags & 0xFF)
        
        // 写入 attrs
        data[8 + pathBytes.size] = UInt8((attrs >> 24) & 0xFF)
        data[9 + pathBytes.size] = UInt8((attrs >> 16) & 0xFF)
        data[10 + pathBytes.size] = UInt8((attrs >> 8) & 0xFF)
        data[11 + pathBytes.size] = UInt8(attrs & 0xFF)
        
        SftpPacket(3u8, requestId, data)
    }

    public static func makeClose(requestId: UInt32, handle: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_CLOSE, requestId, stringToBytes(handle))
    }

    public static func makeRead(requestId: UInt32, handle: String, offset: UInt64, length: UInt32): SftpPacket {
        let handleBytes = stringToBytes(handle)
        let totalSize = 4 + handleBytes.size + 8 + 4  // 句柄长度 + 句柄内容 + 偏移量 + 读取长度
        let data = Array<UInt8>(totalSize, item: 0)
        
        // 写入句柄长度
        let handleLength = UInt32(handleBytes.size)
        data[0] = UInt8((handleLength >> 24) & 0xFF)
        data[1] = UInt8((handleLength >> 16) & 0xFF)
        data[2] = UInt8((handleLength >> 8) & 0xFF)
        data[3] = UInt8(handleLength & 0xFF)
        
        // 写入句柄内容
        for (i in 0..handleBytes.size) {
            data[4 + i] = handleBytes[i]
        }
        
        // 写入偏移量
        let offsetStart = 4 + handleBytes.size
        let offsetBytes = uint64ToBytes(offset)
        for (i in 0..8) {
            data[offsetStart + i] = offsetBytes[i]
        }
        
        // 写入读取长度
        let lengthStart = offsetStart + 8
        let lengthBytes = uint32ToBytes(length)
        for (i in 0..4) {
            data[lengthStart + i] = lengthBytes[i]
        }
        
        return SftpPacket(PacketTypes.FXP_READ, requestId, data)
    }

    public static func makeWrite(requestId: UInt32, handle: String, offset: UInt64, writeData: Array<UInt8>): SftpPacket {
        let handleBytes = stringToBytes(handle)
        let offsetBytes = uint64ToBytes(offset)
        let data = concatBytes([handleBytes, offsetBytes, writeData])
        return SftpPacket(PacketTypes.FXP_WRITE, requestId, data)
    }

    public static func makeOpendir(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_OPENDIR, requestId, stringToBytes(path))
    }

    public static func makeReaddir(requestId: UInt32, handle: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_READDIR, requestId, stringToBytes(handle))
    }

    public static func makeMkdir(requestId: UInt32, path: String, attrs: UInt32): SftpPacket {
        let pathBytes = stringToBytes(path)
        let attrsBytes = uint32ToBytes(attrs)
        let data = concatBytes([pathBytes, attrsBytes])
        return SftpPacket(PacketTypes.FXP_MKDIR, requestId, data)
    }

    public static func makeRmdir(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_RMDIR, requestId, stringToBytes(path))
    }

    public static func makeRemove(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_REMOVE, requestId, stringToBytes(path))
    }

    public static func makeRealpath(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_REALPATH, requestId, stringToBytes(path))
    }

    public static func makeStat(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_STAT, requestId, stringToBytes(path))
    }

    public static func makeLstat(requestId: UInt32, path: String): SftpPacket {
        return SftpPacket(PacketTypes.FXP_LSTAT, requestId, stringToBytes(path))
    }
  
}