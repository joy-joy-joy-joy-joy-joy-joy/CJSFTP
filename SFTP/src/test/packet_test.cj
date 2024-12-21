package sftp.test

import sftp.packet.SftpPacket
import sftp.constants.PacketTypes
import sftp.server.SftpServer
import std.fs.*
import std.collection.HashMap
import std.io.*

@Test
class PacketTest {
    @TestCase
    func testNormalCase() {
        // 测试用例1：基本数据包
        let testData1 = Array<UInt8>(3, item:0)
        testData1[0] = b'1'
        testData1[1] = b'2'
        testData1[2] = b'3'
        verifyPacket(UInt8(1), UInt32(1), testData1)
        
        // 测试用例2：最大值测试
        let testData2 = Array<UInt8>(11, item:0)
        for (i in 0..11) {
            testData2[i] = b'a' + UInt8(i)
        }
        verifyPacket(UInt8(255), UInt32(0xFFFFFFFF), testData2)
        
        // 测试用例3：空数据测试
        let testData3 = Array<UInt8>(0, item:0)
        verifyPacket(UInt8(128), UInt32(65535), testData3)
    }

    @TestCase
    func testBoundaryCase() {
        // 1. 最小包(只有头部)
        let minPacket = SftpPacket(0, 0, Array<UInt8>(0, item:0))
        let encoded = minPacket.encode()
        match (SftpPacket.decode(encoded)) {
            case Some(_) => println("最小包测试通过")
            case None => @Fail("最小包解码失败")
        }
        
        // 2. 大数据包测试
        let largeData = Array<UInt8>(1024 * 1024, item:0xFF) // 1MB数据
        let largePacket = SftpPacket(1, 1, largeData)
        let largeEncoded = largePacket.encode()
        match (SftpPacket.decode(largeEncoded)) {
            case Some(decoded) => @Assert(decoded.data.size == largeData.size)
            case None => @Fail("大数据包解码失败")
        }
    }

    @TestCase
    func testErrorCase() {
        // 1. 数据包太短
        let shortData = Array<UInt8>(8, item:0)
        match (SftpPacket.decode(shortData)) {
            case None => println("短数据包测试通过")
            case Some(_) => @Fail("未能检测出数据包过短")
        }
        
        // 2. 长度字段错误
        var invalidLenData = Array<UInt8>(12, item:0)
        invalidLenData[0] = 0xFF
        invalidLenData[1] = 0xFF
        invalidLenData[2] = 0xFF
        invalidLenData[3] = 0xFF
        match (SftpPacket.decode(invalidLenData)) {
            case None => println("无效长度测试通过")
            case Some(_) => @Fail("未能检测出无效长度")
        }
        
        // 3. 数据被截断
        let packet = SftpPacket(1, 1, Array<UInt8>(100, item:0))
        let encoded = packet.encode()
        let truncated = Array<UInt8>(encoded[0..50])
        match (SftpPacket.decode(truncated)) {
            case None => println("截断数据测试通过")
            case Some(_) => @Fail("未能检测出数据被截断")
        }
    }

    private func verifyPacket(type_: UInt8, requestId: UInt32, data: Array<UInt8>) {
        let packet = SftpPacket(type_, requestId, data)
        let encoded = packet.encode()
        
        match (SftpPacket.decode(encoded)) {
            case Some(decoded) => try {
                @Assert(decoded.type_ == type_)
                @Assert(decoded.requestId == requestId)
                @Assert(decoded.data.size == data.size)
                println("测试通过: type=${type_}, id=${requestId}, size=${data.size}")
            } catch (e: Exception) {
                @Fail("测试失败: " + e.message)
            }
            case None => @Fail("解码失败: type=${type_}, id=${requestId}, size=${data.size}")
        }
    }
}