package sftp.version

import sftp.packet.SftpPacket
import sftp.constants.PacketTypes

// 版本特性接口
public interface VersionFeatures {
    func supportsSymlink(): Bool
    func supportsRename(): Bool
    func supportsTimestamp(): Bool
    func supportsExtendedAttributes(): Bool
    func supportsACL(): Bool
    func maxPacketSize(): UInt32
}

// 基础版本接口
public open class BaseVersion {
    private var version: UInt32
    private var nextRequestId: UInt32 = 1u32
    
    init(version: UInt32) {
        this.version = version
    }
    
    public func getVersion(): UInt32 {
        version
    }
    
    protected func getNextRequestId(): UInt32 {
        let id = nextRequestId
        nextRequestId += 1u32
        id
    }
}

// Version1 特性实现
public class Version1Features <: VersionFeatures {
    public func supportsSymlink(): Bool { false }
    public func supportsRename(): Bool { false }
    public func supportsTimestamp(): Bool { false }
    public func supportsExtendedAttributes(): Bool { false }
    public func supportsACL(): Bool { false }
    public func maxPacketSize(): UInt32 { 32768u32 }
}

// Version1 实现
public class Version1 <: BaseVersion {
    private var features: Version1Features
    
    init() {
        super(1u32)
        features = Version1Features()
    }
    
    public func getFeatures(): VersionFeatures {
        features
    }
    
    // 基础文件操作 - v1支持的操作
    public func open(path: String, flags: UInt32, attrs: UInt32): SftpPacket {
        SftpPacket.makeOpen(getNextRequestId(), path, flags, attrs)
    }
    
    public func close(handle: String): SftpPacket {
        SftpPacket.makeClose(getNextRequestId(), handle)
    }
    
    public func read(handle: String, offset: UInt64, length: UInt32): SftpPacket {
        SftpPacket.makeRead(getNextRequestId(), handle, offset, length)
    }
    
    public func write(handle: String, offset: UInt64, data: Array<UInt8>): SftpPacket {
        SftpPacket.makeWrite(getNextRequestId(), handle, offset, data)
    }
    
    public func stat(path: String): SftpPacket {
        SftpPacket.makeStat(getNextRequestId(), path)
    }
    
    public func opendir(path: String): SftpPacket {
        SftpPacket.makeOpendir(getNextRequestId(), path)
    }
    
    public func readdir(handle: String): SftpPacket {
        SftpPacket.makeReaddir(getNextRequestId(), handle)
    }
    
    public func mkdir(path: String, attrs: UInt32): SftpPacket {
        SftpPacket.makeMkdir(getNextRequestId(), path, attrs)
    }
    
    public func rmdir(path: String): SftpPacket {
        SftpPacket.makeRmdir(getNextRequestId(), path)
    }
    
    public func remove(path: String): SftpPacket {
        SftpPacket.makeRemove(getNextRequestId(), path)
    }
    
    public func realpath(path: String): SftpPacket {
        SftpPacket.makeRealpath(getNextRequestId(), path)
    }
}

// 其他版本的占位定义
public class Version2 <: BaseVersion {
    init() { super(2u32) }
}

public class Version3 <: BaseVersion {
    init() { super(3u32) }
}

public class Version4 <: BaseVersion {
    init() { super(4u32) }
}

public class Version5 <: BaseVersion {
    init() { super(5u32) }
}

public class Version6 <: BaseVersion {
    init() { super(6u32) }
}

// 版本管理器
public class VersionManager {
    private var currentVersion: BaseVersion
    
    public init() {
        this.currentVersion = Version1()  // 默认使用v1
    }
    
    public func negotiateVersion(clientVersion: UInt32): UInt32 {
        let version = if (clientVersion > 6u32) {
            6u32
        } else if (clientVersion < 1u32) {
            1u32
        } else {
            clientVersion
        }
        
        currentVersion = match (version) {
            case 6u32 => Version6()
            case 5u32 => Version5()
            case 4u32 => Version4()
            case 3u32 => Version3()
            case 2u32 => Version2()
            case _ => Version1()
        }
        
        version
    }
    
    public func getCurrentVersion(): BaseVersion {
        currentVersion
    }
}