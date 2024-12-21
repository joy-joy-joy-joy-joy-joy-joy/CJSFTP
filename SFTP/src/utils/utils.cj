package sftp.utils

 // 辅助函数：从字节数组中读取字符串
public func readString(data: Array<UInt8>, offset: Int64): String {
    let length = readUInt32(data, offset)
    let start = offset + Int64(4)
    let end = start + Int64(length)
    let bytes = data[start..end]
    String.fromUtf8(bytes)  // 使用 fromUtf8 方法
}

public func readUInt32(data: Array<UInt8>, offset: Int64): UInt32 {
    (UInt32(data[offset]) << 24) |
    (UInt32(data[offset + 1]) << 16) |
    (UInt32(data[offset + 2]) << 8) |
    UInt32(data[offset + 3])
}

public func readUInt64(data: Array<UInt8>, offset: Int64): UInt64 {
    (UInt64(data[offset]) << 56) |
    (UInt64(data[offset + 1]) << 48) |
    (UInt64(data[offset + 2]) << 40) |
    (UInt64(data[offset + 3]) << 32) |
    (UInt64(data[offset + 4]) << 24) |
    (UInt64(data[offset + 5]) << 16) |
    (UInt64(data[offset + 6]) << 8) |
    UInt64(data[offset + 7])
}

// 工具方法 - 合并字节数组
public func concatBytes(arrays: Array<Array<UInt8>>): Array<UInt8> {
    var totalSize = 0
    for (arr in arrays) {
        totalSize += arr.size
    }
    
    var result = Array<UInt8>(totalSize, item:0)
    var pos = 0
    
    for (arr in arrays) {
        for (i in 0..arr.size) {
            result[pos] = arr[i]
            pos += 1
        }
    }
    
    return result
}