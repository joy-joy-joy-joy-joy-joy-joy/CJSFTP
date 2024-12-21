// src/constants/constants.cj
package sftp.constants

// SFTP 协议包类型常量
public class PacketTypes {
    // 初始化和版本
    public static let FXP_INIT: UInt8 = 1
    public static let FXP_VERSION: UInt8 = 2
    
    // 文件操作
    public static let FXP_OPEN: UInt8 = 3
    public static let FXP_CLOSE: UInt8 = 4
    public static let FXP_READ: UInt8 = 5
    public static let FXP_WRITE: UInt8 = 6
    public static let FXP_LSTAT: UInt8 = 7
    public static let FXP_FSTAT: UInt8 = 8
    public static let FXP_SETSTAT: UInt8 = 9
    public static let FXP_FSETSTAT: UInt8 = 10
    public static let FXP_OPENDIR: UInt8 = 11
    public static let FXP_READDIR: UInt8 = 12
    public static let FXP_REMOVE: UInt8 = 13
    public static let FXP_MKDIR: UInt8 = 14
    public static let FXP_RMDIR: UInt8 = 15
    public static let FXP_REALPATH: UInt8 = 16
    public static let FXP_STAT: UInt8 = 17
    public static let FXP_RENAME: UInt8 = 18
    public static let FXP_READLINK: UInt8 = 19
    public static let FXP_SYMLINK: UInt8 = 20
    
    // 响应类型
    public static let FXP_STATUS: UInt8 = 101
    public static let FXP_HANDLE: UInt8 = 102
    public static let FXP_DATA: UInt8 = 103
    public static let FXP_NAME: UInt8 = 104
    public static let FXP_ATTRS: UInt8 = 105
    
    // 扩展类型
    public static let FXP_EXTENDED: UInt8 = 200
    public static let FXP_EXTENDED_REPLY: UInt8 = 201
}

// 文件打开标志
public class OpenFlags {
    public static let READ: UInt32 = 0x00000001
    public static let WRITE: UInt32 = 0x00000002
    public static let APPEND: UInt32 = 0x00000004
    public static let CREATE: UInt32 = 0x00000008
    public static let TRUNCATE: UInt32 = 0x00000010
    public static let EXCL: UInt32 = 0x00000020
}

// 状态码
public class StatusCodes {
    public static let OK: UInt32 = 0
    public static let EOF: UInt32 = 1
    public static let NO_SUCH_FILE: UInt32 = 2
    public static let PERMISSION_DENIED: UInt32 = 3
    public static let FAILURE: UInt32 = 4
    public static let BAD_MESSAGE: UInt32 = 5
    public static let NO_CONNECTION: UInt32 = 6
    public static let CONNECTION_LOST: UInt32 = 7
    public static let OP_UNSUPPORTED: UInt32 = 8
}

// 属性标志
public class AttributeFlags {
    public static let SIZE: UInt32 = 0x00000001
    public static let UIDGID: UInt32 = 0x00000002
    public static let PERMISSIONS: UInt32 = 0x00000004
    public static let ACMODTIME: UInt32 = 0x00000008
    public static let EXTENDED: UInt32 = 0x80000000
}