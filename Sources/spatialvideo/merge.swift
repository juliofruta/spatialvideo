//
//  File.swift
//  
//
//  Created by Julio Cesar Guzman Villanueva on 2/22/24.
//

import Foundation
import AVFoundation

func merge(videoUrl: URL, with audioUrl: URL) async throws -> URL {
    let composition = AVMutableComposition()
    // Add video track
    let videoAsset = AVURLAsset(url: videoUrl)
    guard let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
        throw NSError(domain: "Failed to add video track", code: 0, userInfo: nil)
    }
    guard let videoAssetTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
        throw NSError(domain: "Failed to get video asset track", code: 0, userInfo: nil)
    }
    do {
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: await videoAsset.load(.duration)), of: videoAssetTrack, at: .zero)
    } catch {
        throw error
    }
    
    // Add audio track
    let audioAsset = AVURLAsset(url: audioUrl)
    guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw NSError(domain: "Failed to add audio track", code: 0, userInfo: nil)
    }
    guard let audioAssetTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first else {
        throw NSError(domain: "Failed to get audio asset track", code: 0, userInfo: nil)
    }
    do {
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: await videoAsset.load(.duration)), of: audioAssetTrack, at: .zero)
    } catch {
        throw error
    }
    
    // Export composition
    let fileManager = FileManager.default
    let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let outputURL = documentDirectory.appendingPathComponent("output.mp4")
    
    guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw NSError(domain: "Failed to create export session", code: 0, userInfo: nil)
    }
    
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mov
    await exportSession.export()
    return outputURL
}
