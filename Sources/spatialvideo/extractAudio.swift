//
//  File.swift
//  
//
//  Created by Julio Cesar Guzman Villanueva on 2/22/24.
//

import Foundation
import AVFoundation

func extractAudio(from videoUrl: URL) async throws -> URL {
    let asset = AVURLAsset(url: videoUrl)
    guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "Video does not contain audio track", code: 0, userInfo: nil)
    }
    
    let composition = AVMutableComposition()
    guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw NSError(domain: "Failed to create composition audio track", code: 0, userInfo: nil)
    }
    
    do {
        try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: await asset.load(.duration)), of: audioTrack, at: .zero)
    } catch {
        throw error
    }
    
    let fileManager = FileManager.default
    let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    let outputUrl = documentsDirectory.appendingPathComponent("extracted_audio.m4a")
    
    if fileManager.fileExists(atPath: outputUrl.path) {
        do {
            try fileManager.removeItem(at: outputUrl)
        } catch {
            throw error
        }
    }
    
    let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
    exportSession?.outputURL = outputUrl
    exportSession?.outputFileType = .m4a
    await exportSession?.export()
    return outputUrl
}
