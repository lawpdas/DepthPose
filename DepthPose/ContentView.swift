//
//  ContentView.swift
//  DepthPose
//
//  Created by space on 2021/12/29.
//

import ARKit
import RealityKit
import UIKit
import SwiftUI
import Foundation

struct RealityKitView: UIViewRepresentable {
    @Binding var recordState: Bool
    @Binding var showInfo: String
    

    func makeUIView(context: Context) -> ARView {
        let view = ARView()

        // start AR session
        let session = view.session

        let config = ARWorldTrackingConfiguration()

        config.worldAlignment = .gravityAndHeading // right hand, fix the direction of three axes to real-world: +x(East), +y(Up), -z(North)

        config.isAutoFocusEnabled = true
        
        config.isLightEstimationEnabled = false
        
        if type(of: config).supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        } else {
            
        }
        
//        config.planeDetection = [.horizontal]
        session.run(config)

//        // Add coaching overlay
//        let coachingOverlay = ARCoachingOverlayView()
//        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        coachingOverlay.session = session
//        coachingOverlay.goal = .horizontalPlane
//        view.addSubview(coachingOverlay)
//
//        // set debug options
//        view.debugOptions = [.showFeaturePoints, .showAnchorOrigins, .showAnchorGeometry]
        
        view.debugOptions = [.showWorldOrigin]
        
        
        // Handle ARSession events via delegate
        context.coordinator.view = view
        session.delegate = context.coordinator

        return view
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(recordState: $recordState, showInfo: $showInfo)
    }
   
    
}

extension RealityKitView {
    class Coordinator: NSObject, ARSessionDelegate {
        
        weak var view: ARView?
        
        @Binding var recordState: Bool
        @Binding var showInfo: String

        
        var folderName: String? = nil
        var frameNum: Int64 = 0
        var saveDict = [String:Any]()
        var lastTime = 0.0
        
        var context: CIContext = CIContext(options: nil)

        init(recordState: Binding<Bool>, showInfo: Binding<String>) {
            self._recordState = recordState
            self._showInfo = showInfo
        }

    
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            
             
            if recordState {
                if folderName == nil {

                    folderName = getCurrentTime()
                }
                
            
                DispatchQueue.global(qos: .userInitiated).async {
                    let camera = frame.camera
                    let timeStamp: String = String(format: "%f", frame.timestamp)
                    
//                    let depthMap = frame.sceneDepth?.depthMap
//                    let depthConf = frame.sceneDepth?.confidenceMap
                    
                    // get save path
                    let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let folderPath = path.appendingPathComponent(self.folderName!)
                    
                    // create folder
                    if FileManager.default.fileExists(atPath: folderPath.path) == false {
                        do {
                            try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            self.showInfo += "Create folder failed;"
                            print(error)
                        }
                    }

                    // convert CVPixelBuffer to UIImage and save it as JPEG image
                    let rgbImage: Data? = self.convertImage(frame.capturedImage).jpegData(compressionQuality: 0.75)
                    let rgbPath = folderPath.appendingPathComponent(timeStamp + ".jpg")
                    
                    // save to file
                    do {
                        try rgbImage?.write(to: rgbPath)
                    } catch {
                        self.showInfo += "Save RBG image failed; "
                        print(error)
                    }
                    
                    // append current frame
                    self.saveDict[timeStamp] = [
                        "transformMat": self.arrayFromTransform(camera.transform),
                        "eulrAngle": self.arrayFromAngles(camera.eulerAngles),
                    ]
                    
                    self.frameNum += 1
                    
                    
                    self.showInfo = String(format: "FPS: %d | Frames: %d\n", Int(1/(frame.timestamp - self.lastTime)), self.frameNum)
                    self.showInfo += String(format: "X: %4d, Y: %4d, Z: %4d",
                                            Int(camera.eulerAngles.x / Float32.pi * 180),
                                            Int(camera.eulerAngles.y / Float32.pi * 180),
                                            Int(camera.eulerAngles.z / Float32.pi * 180))
                    
                    self.lastTime = frame.timestamp
                }

        

            } else {
                
                if saveDict.isEmpty == false && folderName != nil {
                    
                    self.saveDict["FrameNum"] = frameNum
                    
//                    DispatchQueue.global(qos: .userInitiated).async {
                        // get save path
                        let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let jsonPath = path.appendingPathComponent(self.folderName!).appendingPathComponent(self.folderName! + ".json")

                        // convert Dictionary to JSON string and save it
                        let jsonData = try? JSONSerialization.data(withJSONObject: self.saveDict, options: .prettyPrinted)
                        let jsonString = String(data: jsonData!, encoding: String.Encoding.ascii)
                        
                        // save to file
                        do {
                            try jsonString?.write(to: jsonPath, atomically: true, encoding: .utf8)
                        } catch {
                            self.showInfo += "Save JSON failed;"
                            print(error)
                        }
                        
                        // clear saveDict
                        self.saveDict = [String:Any]()
//                    }
                    
                    self.folderName = nil
                    self.frameNum = 0
                } else {
                    let camera = frame.camera
                    showInfo = "Press the button to record >>>\n"
                    showInfo += String(format: "X: %4d, Y: %4d, Z: %4d",
                                       Int(camera.eulerAngles.x / Float32.pi * 180),
                                       Int(camera.eulerAngles.y / Float32.pi * 180),
                                       Int(camera.eulerAngles.z / Float32.pi * 180))
                    showInfo += String(format: " | X: %.2f, Y: %.2f, Z: %.2f", camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)

                }

                
            }
            
        }

        func getCurrentTime() -> String {
            let date = Date()
            let calendar = Calendar.current
            let timeString = (
                String(calendar.component(.year, from: date)) +
                String(calendar.component(.month, from: date)) +
                String(calendar.component(.day, from: date)) + "-" +
                String(calendar.component(.hour, from: date)) +
                String(calendar.component(.minute, from: date)) +
                String(calendar.component(.second, from: date))
            )
            return timeString
        }
        
        func arrayFromTransform(_ transform: simd_float4x4) -> [[Float]] {
            var array: [[Float]] = Array(repeating: Array(repeating: Float(), count: 4), count: 4)
            array[0] = [transform.columns.0.x, transform.columns.1.x, transform.columns.2.x, transform.columns.3.x]
            array[1] = [transform.columns.0.y, transform.columns.1.y, transform.columns.2.y, transform.columns.3.y]
            array[2] = [transform.columns.0.z, transform.columns.1.z, transform.columns.2.z, transform.columns.3.z]
            array[3] = [transform.columns.0.w, transform.columns.1.w, transform.columns.2.w, transform.columns.3.w]
            return array
        }
        
        func arrayFromAngles(_ eulr_angles: simd_float3) -> [Float] {
            var array: [Float] = Array(repeating: Float(), count: 3)
            array = [eulr_angles.x / Float32.pi * 180, eulr_angles.y / Float32.pi * 180, eulr_angles.z / Float32.pi * 180]
            return array
        }
        
        func convertImage(_ pixelBuf: CVPixelBuffer) -> UIImage {
            let ciImage = CIImage(cvPixelBuffer: pixelBuf)
//            let context = CIContext(options: nil)
            let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
            let uiImage = UIImage(cgImage: cgImage!)
            return uiImage
        }
        
//        func convertRawDepth(_ pixelBuf: CVPixelBuffer) ->[[Float32]] {
//            let w = CVPixelBufferGetWidth(pixelBuf)
//            let h = CVPixelBufferGetHeight(pixelBuf)
//            var array: [[Float]] = Array(repeating: Array(repeating: Float(), count: w), count: h)
//
//            CVPixelBufferRef
//
//            CVPixelBufferLockBaseAddress(pixelBuf, CVPixelBufferLockFlags(rawValue: 0))
//            let floatBuf = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuf), to: UnsafeMutablePointer &amp;amp;amp;lt;Float32&amp;amp;gt;.self)
//
//            for y in 0...(h-1) {
//                var row = [Float32]()
//                for x in 0...(w-1) {
//                    row.append(floatBuf[y * w + x])
//                }
//                array.append(row)
//            }
//            return array
//        }
        
    }
}

struct ContentView: View {
    @State private var showInfo: String = "Press the button to record >>>\n"
    @State private var showImage: String = "play.fill"
    @State private var recordState: Bool = false

    let initShow = "Press the button to record >>>\n"

    var body: some View {
        
        
        ZStack {
            RealityKitView(recordState: $recordState, showInfo: $showInfo)
                .ignoresSafeArea()
            VStack {
                Spacer()
                HStack {
                    Text(showInfo)
                        .padding()
                    Spacer()
                    Button(action: {
                        withAnimation {
                            if showImage == "play.fill" {
                                showImage = "stop.fill"
                                recordState = true
                                
    //                            DispatchQueue.global(qos: .userInitiated).async {
    //                                testFunc()
    //                                showInfo = "Recording ..."
    //                            }
                                
                            } else {
                                showImage = "play.fill"
                                showInfo = initShow
                                recordState = false
                            }
                        }
                    }) {
                        Image(systemName: showImage)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
                .background(Color.gray.opacity(0.5))
            }
        }
    }
    
    func testFunc() {
        var saveDict = [String: Any]()
        let transform: [[Float]] = Array(repeating: Array(repeating: Float(), count: 4), count: 4)
        let angles: [Float] = Array(repeating: Float(), count: 3)
        
        saveDict[getCurrentTime()] = [
            "timeStamp": "timeStamp1",
            "transformMat": transform,
            "eulrAngle": angles,
        ]
        
        saveDict[getCurrentTime()] = [
            "timeStamp": "timeStamp2",
            "transformMat": transform,
            "eulrAngle": angles,
        ]

        let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let folderPath = path.appendingPathComponent("Data")
        if FileManager.default.fileExists(atPath: folderPath.path) == false {
            do {
                try FileManager.default.createDirectory(at: folderPath, withIntermediateDirectories: true, attributes: nil)
            } catch {
                showInfo = "Make folder failed!"
                print(error)
            }
        }
        
        // convert Dictionary to JSON string and save it
        let jsonData = try? JSONSerialization.data(withJSONObject: saveDict, options: .prettyPrinted)
        let jsonString = String(data: jsonData!, encoding: String.Encoding.ascii)
        let jsonPath = folderPath.appendingPathComponent(getCurrentTime() + ".json")
        
        do {
            try jsonString?.write(to: jsonPath, atomically: true, encoding: .utf8)
        } catch {
            showInfo += "; Save JSON failed!"
            print(error)
        }
        
        // convert CVPixelBuffer to UIImage and save it as JPEG image
        let image = UIImage(named: "test")
        let rgbImage: Data? = image?.jpegData(compressionQuality: 0.3)
        let rgbPath = folderPath.appendingPathComponent(getCurrentTime() + ".jpg")
        
        // save to file
        do {
            try rgbImage?.write(to: rgbPath)
        } catch {
            self.showInfo += "; Save RBG image failed!"
            print(error)
        }
        
    }
    
    func resizedImage(at url: URL, for size: CGSize) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(url as NSURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
        else {
            return nil
        }
        
        return UIImage(cgImage: image)
    }
    
    func getCurrentTime() -> String {
        let date = Date()
        let calendar = Calendar.current
        let timeString = (
            String(calendar.component(.year, from: date)) +
            String(calendar.component(.month, from: date)) +
            String(calendar.component(.day, from: date)) + "-" +
            String(calendar.component(.hour, from: date)) +
            String(calendar.component(.minute, from: date)) +
            String(calendar.component(.second, from: date))
        )
        return timeString
    }

}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.portraitUpsideDown)
    }
}
