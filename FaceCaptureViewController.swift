//
//  FaceCaptureViewController.swift
//  demo
//
//  Created by 付文华 on 2020/12/14.
//  Copyright © 2020 natsu. All rights reserved.
//

import UIKit

class FaceCaptureViewController: ViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var popClosure: (() -> Void)?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
    }
    var countDown: Int = 3
    let gcdTimer = DispatchSource.makeTimerSource()
    override func viewDidLoad() {
        super.viewDidLoad()
        preview.frame = self.view.bounds
        self.view.layer.addSublayer(preview)
        session.startRunning()
        view.addSubview(tipLabel)
        view.addSubview(tipTime)
        tipTime.snp.makeConstraints { (make) in
            make.centerX.equalToSuperview()
            make.top.equalTo(tipLabel.snp.bottom).offset(20)
            make.size.equalTo(CGSize(width: 50, height: 50))
        }
        
        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = [0.5, 0.3, 0.2]
        opacityAnimation.duration = 1
        opacityAnimation.repeatCount = self.countDown.float
        opacityAnimation.isRemovedOnCompletion = true
        opacityAnimation.fillMode = .forwards
        tipTime.layer.add(opacityAnimation, forKey: "groupAnimation")
        
        gcdTimer.schedule(wallDeadline: DispatchWallTime.now(), repeating: DispatchTimeInterval.seconds(1), leeway: DispatchTimeInterval.seconds(0))

        gcdTimer.setEventHandler {
            DispatchQueue.main.async {
                self.countDown -= 1
                self.tipTime.text = "\(self.countDown)"
            }
        }
        gcdTimer.resume()
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) {
            if !self.isPop {
                self.letgo()
            }
        }
    }
    private var isPop: Bool = false
    private func letgo() {
        isPop = true
        self.session.stopRunning()
        self.gcdTimer.cancel()
        self.popClosure?()
        self.popViewController()
    }
    
    // ui
    lazy var tipLabel: UILabel = {
        let l = UILabel(frame: CGRect(x: 20, y: 50, width: ScreenWidth - 40, height: 80))
        l.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        l.textAlignment = .center
        l.textColor = .init(hex: "ddd")
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.text = "实名认证中"
        l.cornerRadius = 2
        return l
    }()
    lazy var tipTime: UILabel = {
        let b = UILabel()
        b.backgroundColor = .init(hex: "293874")
        b.cornerRadius = 25
        b.layer.opacity = 0.2
        b.textColor = .white
        b.text = "2"
        b.textAlignment = .center
        b.font = .systemFont(ofSize: 24, weight: .bold)
//        b.setTitle("3", for: .normal)
        
        return b
    }()
    
    // AVFoundation
    
    lazy var preview: AVCaptureVideoPreviewLayer = {
        let p = AVCaptureVideoPreviewLayer(session: session)
        p.videoGravity = .resizeAspectFill
        return p
    }()
    lazy var session: AVCaptureSession = {
        let session = AVCaptureSession()
        session.canSetSessionPreset(.vga640x480)
        if let input = captureInput {
            session.addInput(input)
            session.addOutput(captureOutput)
            session.addOutput(captureImageOutput)
        }
        return session
    }()
    lazy var device: AVCaptureDevice? = {
        let dss = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        return dss.devices.first
    }()
    lazy var captureInput: AVCaptureDeviceInput? = {
        if let d = device {
            let ci = try? AVCaptureDeviceInput(device: d)
            return ci
        }
        return nil
    }()
    lazy var captureOutput: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        return output
    }()
    lazy var captureImageOutput: AVCapturePhotoOutput = {
        let o = AVCapturePhotoOutput()
        o.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey:AVVideoCodecJPEG])], completionHandler: nil)
        
        return o
    }()
    
    lazy var queue: DispatchQueue = {
        let q = DispatchQueue(label: "cameraQueue")
        return q
    }()
    
    deinit {
        print("==============deinit")
//        gcdTimer.cancel()
    }

}

extension FaceCaptureViewController {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
         
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let newContext = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return
        }
        newContext.concatenate(CGAffineTransform(rotationAngle: CGFloat.pi/2))
        guard let newImage = newContext.makeImage() else { return }
        
        let image = UIImage(cgImage: newImage, scale: 1, orientation: .leftMirrored)
        performSelector(onMainThread: #selector(detectFace(_:)), with: image, waitUntilDone: true)
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    @objc func detectFace(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeFace, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyLow])
        
        var exifOrientation: Int = 1
        switch image.imageOrientation {
        case .up:
            exifOrientation = 1
        case .down:
            exifOrientation = 3
        case .left:
            exifOrientation = 8
        case .right:
            exifOrientation = 6
        case .upMirrored:
            exifOrientation = 2
        case .downMirrored:
            exifOrientation = 4
        case .leftMirrored:
            exifOrientation = 5
        case .rightMirrored:
            exifOrientation = 7
        default:
            break
        }
        // options要在这里设置，在detector初始化的地方设置无效
        guard let features = detector?.features(in: ciImage, options: [CIDetectorImageOrientation: exifOrientation, CIDetectorEyeBlink: true]) as? [CIFaceFeature] else { return }
        // 只取第一张人脸
        guard let faceObject = features.first else { return }
        
        if faceObject.hasMouthPosition && faceObject.hasLeftEyePosition && faceObject.hasRightEyePosition && !faceObject.leftEyeClosed && !faceObject.rightEyeClosed {
            print("------------------found face, lefteye closed=\(faceObject.leftEyeClosed) righteye closed=\(faceObject.rightEyeClosed)")
            // TODO: - 上传图片
            
            self.letgo()
        }
    }
}
