import Foundation
@preconcurrency import AVFoundation
import CoreMedia
import VideoToolbox

/// This sample uses the left eye for video layer ID 0 (the hero eye) and the right eye for layer ID 1.
/// - Tag: VideoLayers
let MVHEVCVideoLayerIDs = [0, 1]

enum Error: Swift.Error {
    case errorLoadingSideBySeideVideoInput
    case unknownError
    case applyingOutputSettings
    case addingSideBySideVideoFramesAsInput
    case addingAudioAsInput
    case failedToStartWritingMultiviewOutputFile
    case failedToCreatePixelTransfer
    
}

/// Transcodes side-by-side HEVC to MV-HEVC.
@available(macOS 14.0, *)
/// Loads a video to read for conversion.
/// - Parameter url: A URL to a side-by-side HEVC file.
/// - Tag: ReadInputVideo
public func spatialVideo(from sideToSideVideoURL: URL) async throws -> URL {
    let sideToSideVideoAsset = AVURLAsset(url: sideToSideVideoURL)
    let sideToSideVideoReader = try AVAssetReader(asset: sideToSideVideoAsset)
    // Get the side-by-side video track.
    guard let sideToSideVideoTrack = try await sideToSideVideoAsset.loadTracks(withMediaCharacteristic: .visual).first else {
        throw Error.errorLoadingSideBySeideVideoInput
    }
    guard let audioTrack = try await sideToSideVideoAsset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "Video does not contain audio track", code: 0, userInfo: nil)
    }
    let sideBySideFrameSize = try await sideToSideVideoTrack.load(.naturalSize)
    let eyeFrameSize = CGSize(width: sideBySideFrameSize.width / 2, height: sideBySideFrameSize.height)
    let readerSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
    ]
    let sideBySideTrack = AVAssetReaderTrackOutput(track: sideToSideVideoTrack, outputSettings: readerSettings)
    if sideToSideVideoReader.canAdd(sideBySideTrack) {
        sideToSideVideoReader.add(sideBySideTrack)
    }
    let audioTrackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
    if sideToSideVideoReader.canAdd(audioTrackOutput) {
        sideToSideVideoReader.add(audioTrackOutput)
    }
    
    if !sideToSideVideoReader.startReading() {
        throw sideToSideVideoReader.error ?? Error.unknownError
    }
    let spatialVideoFileName = sideToSideVideoURL.deletingPathExtension().lastPathComponent + "_MVHEVC.mov"
    let spatialVideoURL = sideToSideVideoURL.deletingLastPathComponent().appendingPathComponent(spatialVideoFileName)
    if FileManager.default.fileExists(atPath: spatialVideoURL.path(percentEncoded: true)) {
        try FileManager.default.removeItem(at: spatialVideoURL)
    }
    await transcodeToMVHEVC(output: spatialVideoURL)
   
    // Now work with audio
//    let audio = try await extractAudio(from: sideToSideVideoURL)
//    let merge = try await merge(videoUrl: spatialVideoURL, with: audio)
    return spatialVideoURL//merge
    
    /// Transcodes  side-by-side HEVC media to MV-HEVC.
    /// - Parameter output: The output URL to write the MV-HEVC file to.
    /// - Tag: TranscodeVideo
    func transcodeToMVHEVC(output videoOutputURL: URL) async {
        await withCheckedContinuation { continuation in
            Task {
                let multiviewWriter = try AVAssetWriter(outputURL: videoOutputURL, fileType: AVFileType.mov)
                let multiviewCompressionProperties: [String: Any] = [
                    kVTCompressionPropertyKey_MVHEVCVideoLayerIDs as String: MVHEVCVideoLayerIDs,
                    kVTCompressionPropertyKey_MVHEVCViewIDs as String: MVHEVCVideoLayerIDs,
                    kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs as String: MVHEVCVideoLayerIDs,
                    kVTCompressionPropertyKey_HasLeftStereoEyeView as String: true,
                    kVTCompressionPropertyKey_HasRightStereoEyeView as String: true,
                    kVTCompressionPropertyKey_StereoCameraBaseline as String: 63123,
                    kVTCompressionPropertyKey_HeroEye as String: kCMFormatDescriptionHeroEye_Left,
                ]
                
                let multiviewSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: eyeFrameSize.width ,
                    AVVideoHeightKey: eyeFrameSize.height,
                    AVVideoCompressionPropertiesKey: multiviewCompressionProperties,
                ]
        
                let queue = DispatchQueue(label: "Multiview HEVC Writer")
                
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                audioInput.expectsMediaDataInRealTime = false
                
                guard multiviewWriter.canApply(outputSettings: multiviewSettings, forMediaType: AVMediaType.video) else {
                    throw Error.applyingOutputSettings
                }

                let frameInput = AVAssetWriterInput(mediaType: .video, outputSettings: multiviewSettings)
                func createMetadataItem(key: String, value: String) -> AVMutableMetadataItem {
                    let item = AVMutableMetadataItem()
                    item.key = key as (NSCopying & NSObjectProtocol)
                    item.keySpace = AVMetadataKeySpace.quickTimeMetadata
                    item.value = value as (NSCopying & NSObjectProtocol)
                    return item
                }
                
                // Create metadata items for additional metadata
                let metadataItems: [AVMutableMetadataItem] = [
                    createMetadataItem(key: "com.apple.quicktime.spatial.format-version", value: "1.0"),
                    createMetadataItem(key: "com.apple.quicktime.spatial.aggressors-seen", value: "0")
                ]

                // Append metadata items to the output file
                for item in metadataItems {
                    frameInput.metadata.append(item)
                }
                
                let sourcePixelAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: sideBySideFrameSize.width,
                    kCVPixelBufferHeightKey as String: sideBySideFrameSize.height
                ]

                let bufferInputAdapter = AVAssetWriterInputTaggedPixelBufferGroupAdaptor(
                    assetWriterInput: frameInput,
                    sourcePixelBufferAttributes: sourcePixelAttributes
                )

                guard multiviewWriter.canAdd(frameInput) else {
                    throw Error.addingSideBySideVideoFramesAsInput
                }
                multiviewWriter.add(frameInput)
                
                guard multiviewWriter.canAdd(audioInput) else {
                    throw Error.addingAudioAsInput
                }
                multiviewWriter.add(audioInput)
                
//                let metadataInput = AVAssetWriterInput(mediaType: .depthData, outputSettings: nil)
//                if multiviewWriter.canAdd(metadataInput) {
//                    multiviewWriter.add(metadataInput)
//                    let depthMetadataItem = AVTimedMetadataGroup(
//                        items: [.init()],
//                        timeRange: CMTimeRange(
//                            start: CMTime.zero,
//                            duration: CMTime(seconds: 1, preferredTimescale: 1000)
//                        )
//                    )
//                    
//                    metadataInput.append(
//                        .init(
//                            taggedBuffers: [],
//                            presentationTimeStamp: .zero,
//                            duration: .zero,
//                            formatDescription: try CMTaggedBufferGroupFormatDescription(
//                                mediaType: .video, 
//                                mediaSubType: .mpeg4AAC_Spatial
//                            )
//                        )
//                    )
//                    metadataInput.markAsFinished()
//                }
//                
                guard multiviewWriter.startWriting() else {
                    throw Error.failedToStartWritingMultiviewOutputFile
                }
                multiviewWriter.startSession(atSourceTime: CMTime.zero)

                audioInput.requestMediaDataWhenReady(on: queue) {
                    while audioInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = audioTrackOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            break
                        }
                        
                        audioInput.append(sampleBuffer)
                    }
                }
                
                // The dispatch queue executes the closure when media reads from the input file are available.
                frameInput.requestMediaDataWhenReady(on: queue) {
                    var session: VTPixelTransferSession? = nil
                    guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session) == noErr, let session else {
                        fatalError("Failed to create pixel transfer")
                    }
                    var pixelBufferPool: CVPixelBufferPool? = nil
                    
                    if pixelBufferPool == nil {
                        let bufferPoolSettings: [String: Any] = [
                            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
                            kCVPixelBufferWidthKey as String: eyeFrameSize.width,
                            kCVPixelBufferHeightKey as String: eyeFrameSize.height,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
                        ]
                        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, bufferPoolSettings as NSDictionary, &pixelBufferPool)
                    }
                        
                    guard let pixelBufferPool else {
                        fatalError("Failed to create pixel buffer pool")
                    }
                    
                    // Handling all available frames within the closure improves performance.
                    while frameInput.isReadyForMoreMediaData && bufferInputAdapter.assetWriterInput.isReadyForMoreMediaData {
                        if let sampleBuffer = sideBySideTrack.copyNextSampleBuffer() {
                            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                                fatalError("Failed to load source samples as an image buffer")
                            }
                            
                            if let taggedBuffers = convertFrame(fromSideBySide: imageBuffer, with: pixelBufferPool, in: session) {
                                let newPTS = sampleBuffer.outputPresentationTimeStamp
                                if !bufferInputAdapter.appendTaggedBuffers(taggedBuffers, withPresentationTime: newPTS) {
                                    print("did not append tagged buffers on presentation time: \(newPTS)")
                                } else {
                                    print("appended buffer on presentation time: \(newPTS)")
                                }
                            } else {
                                print("no tagged buffers")
                            }
                        } else {
                            frameInput.markAsFinished()
                            // Continue
                            multiviewWriter.finishWriting {
                                continuation.resume()
                            }
                            print("no next sample buffer, marked as finished")
                            break
                        }
                    }
                }
            }
        }
    }
    
    /// Splits a side-by-side sample buffer into two tagged buffers for left and right eyes.
    /// - Parameters:
    ///   - fromSideBySide: The side-by-side sample buffer to extract individual eye buffers from.
    ///   - with: The pixel buffer pool used to create temporary buffers for pixel copies.
    ///   - in: The transfer session to perform the pixel transfer.
    /// - Returns: Group of tagged buffers for the left and right eyes.
    /// - Tag: ConvertFrame
    @Sendable func convertFrame(
        fromSideBySide imageBuffer: CVImageBuffer,
        with pixelBufferPool: CVPixelBufferPool,
        in session: VTPixelTransferSession
    ) -> [CMTaggedBuffer]? {
        // Output contains two tagged buffers, left eye frame first.
        var taggedBuffers: [CMTaggedBuffer] = []

        for layerID in MVHEVCVideoLayerIDs {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
            guard let pixelBuffer else {
                fatalError("Failed to create pixel buffer for layer \(layerID)")
            }

            // Crop the transfer region to the current eye.
            let apertureOffset = -(eyeFrameSize.width / 2) + CGFloat(layerID) * eyeFrameSize.width
            let cropRectDict = [kCVImageBufferCleanApertureHorizontalOffsetKey: apertureOffset,
                                  kCVImageBufferCleanApertureVerticalOffsetKey: 0,
                                           kCVImageBufferCleanApertureWidthKey: eyeFrameSize.width,
                                          kCVImageBufferCleanApertureHeightKey: eyeFrameSize.height
            ]
            CVBufferSetAttachment(imageBuffer, kCVImageBufferCleanApertureKey, cropRectDict as CFDictionary, CVAttachmentMode.shouldPropagate)
            VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_CropSourceToCleanAperture)

            // Transfer the image to the pixel buffer.
            guard VTPixelTransferSessionTransferImage(session, from: imageBuffer, to: pixelBuffer) == noErr else {
                fatalError("Error during pixel transfer session for layer \(layerID)")
            }

            // Create and append tagged buffers containing the left and right eye images.
            switch layerID {
            case 0: // Left eye buffer
                let leftTags: [CMTag] = [.videoLayerID(0), .stereoView(.leftEye)]
                let leftBuffer = CMTaggedBuffer(tags: leftTags, buffer: .pixelBuffer(pixelBuffer))
                taggedBuffers.append(leftBuffer)
            case 1: // Right eye buffer
                let rightTags: [CMTag] = [.videoLayerID(1), .stereoView(.rightEye)]
                let rightBuffer = CMTaggedBuffer(tags: rightTags, buffer: .pixelBuffer(pixelBuffer))
                taggedBuffers.append(rightBuffer)
            default:
                fatalError("Invalid video layer \(layerID)")
            }
        }
        
        return taggedBuffers
    }
}


