import AVFoundation
import Foundation

class AudioManager: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession?
    private var recordingStartTime: Date?
    
    @Published var audioLevels: [Float] = []
    
    var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func startRecording() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.record, mode: .default)
            try audioSession?.setActive(true)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("temp_recording.m4a")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            recordingStartTime = Date()
            
            // Start monitoring audio levels for waveform
            startMonitoringAudioLevels()
            
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    func stopRecording() async -> URL? {
        audioRecorder?.stop()
        recordingStartTime = nil
        
        try? audioSession?.setActive(false)
        
        return audioRecorder?.url
    }
    
    private func startMonitoringAudioLevels() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else {
                timer.invalidate()
                return
            }
            
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            
            // Normalize level to 0-1 range
            let normalizedLevel = pow(10, level / 20)
            
            DispatchQueue.main.async {
                self.audioLevels.append(normalizedLevel)
                
                // Keep only last 100 samples for waveform
                if self.audioLevels.count > 100 {
                    self.audioLevels.removeFirst()
                }
            }
        }
    }
}
