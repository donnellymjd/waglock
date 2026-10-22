// Synthetic silent video for disposable simulator UI checks; reads no user media.
import AVFoundation
import CoreVideo
import Foundation

let target = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/private/tmp/waglock-ui-sample.mov")
if FileManager.default.fileExists(atPath: target.path) {
    fatalError("Choose a new fixture destination; existing files are never replaced.")
}
let writer = try AVAssetWriter(outputURL: target, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360
])
writer.add(input)
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)
for frame in 0..<90 {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed { throw writer.error! }
        Thread.sleep(forTimeInterval: 0.005)
    }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
          let buffer else { fatalError("Fixture frame allocation failed") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<360 {
        for x in 0..<640 {
            let offset = y * stride + x * 4
            base[offset] = UInt8((x + frame) % 255)
            base[offset + 1] = UInt8((y + frame) % 255)
            base[offset + 2] = 70
            base[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
guard writer.status == .completed else { throw writer.error! }
print(target.path)
