// The Swift Programming Language
// https://docs.swift.org/swift-book


import RxSwift
import UIKit
import AVFoundation
import ReplayKit
import Photos
import RxRelay

enum ReplayBuilderError: Error {
    case alreadyRecording
    case notRecording
    case notRecordingOrAlreadyPaused
    case notPausedOrNotRecording
    case unknown
}

enum ReplayStatus {
    case idle
    case auth
    case authError(error: Error)
    case authSuccess
    case sampleBuffer
    case sampleBufferError(error: Error)
    case stopCaptureing
    case stopCaptureError(error: Error)
    case finishWriting
    case finishWritingError(error: Error)
    case finishWritingSuccess(url: URL)
    case savePhotoing
    case savePhotoError(error: Error)
    case savePhotoSuccess
}

extension ReplayStatus {
    var description: String {
        switch self {
        case .idle:
            return "空闲中"
        case .auth:
            return "授权中"
        case .authError(let error):
            return "授权失败-\(error.localizedDescription)"
        case .authSuccess:
            return "授权成功，马上开始录制"
        case .sampleBuffer:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss" // 自定义格式
            let formattedDate = formatter.string(from: Date())
            return "采样中-\(formattedDate)"
        case .sampleBufferError(let error):
            return "采样失败 \(error.localizedDescription)"
        case .stopCaptureing:
            return "开始停止采样"
        case .stopCaptureError(let error):
            return "停止采样失败\(error.localizedDescription)"
        case .finishWriting:
            return "开始写入数据"
        case .finishWritingError(let error):
            return "写入数据出错\(error.localizedDescription)"
        case .finishWritingSuccess(let url):
            return "写入数据成功 \(url)"
        case .savePhotoing:
            return "开始保存到相册"
        case .savePhotoError(let error):
            return "保存相册失败\(error.localizedDescription)"
        case .savePhotoSuccess:
            return "保存到相册成功"
            
        }
    }
}

public class ReplayBuilder {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private let screenRecorder = RPScreenRecorder.shared()
    private var operations: [(URL?) -> Single<URL?>] = []
    fileprivate var status: BehaviorRelay<ReplayStatus> = BehaviorRelay<ReplayStatus>(value: .idle)

    public init() {}
    
    @discardableResult
    public func setFileName() -> Self {
        let fileName = "\(UUID().uuidString).mp4"
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentsURL.appendingPathComponent(fileName)
        
        operations.append({ url in
            Single.create { single in
                single(.success(fileURL))
                return Disposables.create()
            }
        })
        return self
    }
    
    public func setVideoFileName(fileURL: URL) -> Self {
        operations.append({ _ in
            Single.create { single in
                single(.success(fileURL))
                return Disposables.create()
            }
        })
        return self
    }

    public func setupWriter() -> Self {
        operations.append({ url in
            Single.create { single in
                guard let fileURL = url else {
                    single(.failure(NSError(domain: "SaveError", code: -3, userInfo: nil)))
                    return Disposables.create()
                }
                do {
                    self.assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
                    let outputSettings: [String: Any] = [
                        AVVideoCodecKey: AVVideoCodecType.hevc,
                        AVVideoWidthKey: UIScreen.main.nativeBounds.width,
                        AVVideoHeightKey: UIScreen.main.nativeBounds.height
                    ]
                    self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
                    self.videoInput?.expectsMediaDataInRealTime = true

                    if self.assetWriter!.canAdd(self.videoInput!) {
                        self.assetWriter!.add(self.videoInput!)
                    }
                    single(.success(fileURL))
                } catch {
                    single(.failure(error))
                }
                return Disposables.create()
            }
        })
        
        return self
    }

    @discardableResult
    public func startRecording() -> Self {
        operations.append({ url in
            Single<URL?>.create { single in
                self.assetWriter?.startWriting()
                self.status.accept(.auth)
                self.screenRecorder.startCapture { sampleBuffer, bufferType, error in
                    if let error = error {
                        self.status.accept(.sampleBufferError(error: error))
                    }
                    if bufferType == .video {
                        DispatchQueue.main.async {
                            self.handleSampleBuffer(sampleBuffer)
                        }
                    }
                } completionHandler: { error in
                    if let error = error {
                        self.status.accept(.sampleBufferError(error: error))
                        single(.failure(error))
                    } else {
                        self.status.accept(.authSuccess)
                        single(.success(url))
                    }
                }
                return Disposables.create()
            }
        })
        return self
    }

    @discardableResult
    public func stopRecording() -> Self {

        operations.append({ _ in
            Single<URL?>.create { single in
                self.status.accept(.stopCaptureing)
                self.screenRecorder.stopCapture { error in
                    if let error = error {
                        self.status.accept(.stopCaptureError(error: error))
                        single(.failure(error))
                        return
                    }
                    
                    self.videoInput?.markAsFinished()
                    self.status.accept(.finishWriting)
                    self.assetWriter?.finishWriting {
                        if self.assetWriter?.status == .completed, let outputURL = self.assetWriter?.outputURL {
                            self.status.accept(.finishWritingSuccess(url: outputURL))
                            single(.success(outputURL))
                        } else {
                            self.status.accept(.finishWritingError(error: self.assetWriter?.error ?? ReplayBuilderError.unknown))
                            single(.failure(self.assetWriter?.error ?? ReplayBuilderError.unknown))
                        }
                    }
                }
                return Disposables.create()
            }
        })
        return self
    }

    @discardableResult
    public func saveToPhotoLibrary() -> Self {
        operations.append({ url in
            Single<URL?>.create { single in
                guard let url = url else {
                    single(.failure(NSError(domain: "SaveError", code: -2, userInfo: nil)))
                    return Disposables.create()
                }
                self.status.accept(.savePhotoing)
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    if success {
                        self.status.accept(.savePhotoSuccess)
                        single(.success(url))
                    } else {
                        self.status.accept(.savePhotoError(error: error ?? NSError(domain: "SaveError", code: -1, userInfo: nil)))
                        single(.failure(error ?? NSError(domain: "SaveError", code: -1, userInfo: nil)))
                    }
                }
                return Disposables.create()
            }
            
        })
        return self
    }

    @discardableResult
    public func addAction(_ action: @escaping (URL?) -> Single<URL?>) -> Self {
        operations.append(action)
        return self
    }

    @discardableResult
    public func exec() -> Single<URL?> {
        guard !operations.isEmpty else {
            return Single.error(NSError(domain: "DemoExecutorError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No operations to execute"]))
        }

        let pipeline = operations.reduce(Single<URL?>.just(nil)) { chain, operation in
            chain.flatMap { item in
                operation(item)
            }
        }
        operations.removeAll() // 清空操作队列
        return pipeline
    }

    private func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferGetPresentationTimeStamp(sampleBuffer).isValid,
              let videoInput = videoInput, videoInput.isReadyForMoreMediaData else { return }
        if case .authSuccess = status.value {
            assetWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        self.status.accept(.sampleBuffer)
        videoInput.append(sampleBuffer)
    }
}



extension ReplayBuilder: ReactiveCompatible {}
extension Reactive where Base: ReplayBuilder {
    var status: Observable<ReplayStatus> {
        return base.status.asObservable()
    }
    
    var statusDescription: Observable<String> {
        return base.status.map(\.description).asObservable()
    }
}
