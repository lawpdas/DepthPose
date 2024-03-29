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

struct ARViewContainer: UIViewRepresentable {
    @Binding var recordState: Bool
    @Binding var recordFrames: Int
    @Binding var showInfo: String
    @Binding var showImage: String

    
    func makeUIView(context: Context) -> ARView {
        let view = ARView()
        
        // start AR session
        let session = view.session
        
        let config = ARWorldTrackingConfiguration()

        config.worldAlignment = .gravityAndHeading // right hand, fix the direction of three axes to real-world: +x(East), +y(Up), -z(North)
        
        let supportFormat = type(of: config).supportedVideoFormats
        print(supportFormat)
        config.videoFormat = supportFormat[0]
        
        config.isAutoFocusEnabled = true
        config.isLightEstimationEnabled = false

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]
        } else {
        }
//        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        session.run(config)
        
        view.debugOptions = [.showWorldOrigin]
        
        // Handle ARSession events via delegate
        context.coordinator.view = view
        session.delegate = context.coordinator
        
        return view
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(recordState: $recordState, recordFrames: $recordFrames, showInfo: $showInfo, showImage: $showImage)
    }
    
}

extension ARViewContainer {
    class Coordinator: NSObject, ARSessionDelegate {
        
        weak var view: ARView?
        
        @Binding var recordState: Bool
        @Binding var recordFrames: Int
        @Binding var showInfo: String
        @Binding var showImage: String

        var folderName: String? = nil
        var frameNum: Int64 = 0
        var saveDict = [String:Any]()
        var lastTime = 0.0
        var last_time = 0.0
        
        var context: CIContext = CIContext(options: nil)

        init(recordState: Binding<Bool>, recordFrames: Binding<Int>, showInfo: Binding<String>, showImage: Binding<String>) {
            self._recordState = recordState
            self._recordFrames = recordFrames
            self._showInfo = showInfo
            self._showImage = showImage
        }
        
//        let semaphore = DispatchSemaphore.init(value: 2)

        func session(_ session: ARSession, didUpdate frame: ARFrame) {

            if recordState {
                if folderName == nil {

                    folderName = getCurrentTime()
                }
                
                let currentT = frame.timestamp
                
                if (currentT - last_time) > 0.02 { // >0.016 ==> 30fps
                    DispatchQueue.global(qos: .userInitiated).async {
//                        self.semaphore.wait()
                    
                        
                        let camera = frame.camera
                        let state = camera.trackingState
                        var tracking_quality: Int
                        
                        switch state {
                        case .normal:
                            tracking_quality = 2
                        case .notAvailable:
                            tracking_quality = 0
                        case .limited(_):
                            tracking_quality = 1
                        }
                        
                        let quality: String = String(format: "Q: %d", tracking_quality)
                        
                        let timeStamp: String = String(format: "%f", frame.timestamp)
                        
                        // get save path
                        let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let folderPath_rgb = path.appendingPathComponent(self.folderName!).appendingPathComponent("rgb")
                        let folderPath_depth = path.appendingPathComponent(self.folderName!).appendingPathComponent("depth")
                        let folderPath_conf = path.appendingPathComponent(self.folderName!).appendingPathComponent("conf")

                        // create folder
                        if FileManager.default.fileExists(atPath: folderPath_rgb.path) == false {
                            do {
                                try FileManager.default.createDirectory(at: folderPath_rgb, withIntermediateDirectories: true, attributes: nil)
                            } catch {
                                self.showInfo += "Create folder failed;"
                                print(error)
                            }
                        }
                        if FileManager.default.fileExists(atPath: folderPath_depth.path) == false {
                            do {
                                try FileManager.default.createDirectory(at: folderPath_depth, withIntermediateDirectories: true, attributes: nil)
                            } catch {
                                self.showInfo += "Create folder failed;"
                                print(error)
                            }
                        }
                        if FileManager.default.fileExists(atPath: folderPath_conf.path) == false {
                            do {
                                try FileManager.default.createDirectory(at: folderPath_conf, withIntermediateDirectories: true, attributes: nil)
                            } catch {
                                self.showInfo += "Create folder failed;"
                                print(error)
                            }
                        }
                    

                        // Save RGB, converting CVPixelBuffer to UIImage and save it as JPEG image
                        let rgbPath = folderPath_rgb.appendingPathComponent(timeStamp + ".jpg")
                        self.convertSaveImage(frame.capturedImage, path: rgbPath)
                        
                        // Save Depth, converting CVPixelBuffer to CIImage and save it as TIFF image
                        let depthPathTIFF = folderPath_depth.appendingPathComponent(timeStamp + ".tiff")
                        self.convertSaveDepthTIFF(frame.sceneDepth!.depthMap, path: depthPathTIFF)
                        
                        // Save Confidence, converting CVPixelBuffer to UIImage and save it as PNG image
                        let confPath = folderPath_conf.appendingPathComponent(timeStamp + ".png")
                        self.convertSaveConfDepth(frame.sceneDepth!.confidenceMap!, path: confPath)
                        
                        // append current fram
                        self.saveDict[timeStamp] = [
                            "transformMat": self.arrayFromTransform(camera.transform),
                            "eulrAngle": self.arrayFromAngles(camera.eulerAngles),
                            "intrinsics": self.arrayFromIntrinsics(camera.intrinsics),
                            "tracking_quality": tracking_quality,
                        ]
                    
                        if self.recordFrames != -1 && self.frameNum == self.recordFrames {
                            self.recordState = false
                            self.recordFrames = -1
                            self.showImage = "play.fill"
                        }
                        
                        self.showInfo = String(format: "FPS: %d | Frames: %d\n", Int(1/(frame.timestamp - self.lastTime)), self.frameNum)
                        self.showInfo += String(format: "X: %4d, Y: %4d, Z: %4d",
                                                Int(camera.eulerAngles.x / Float32.pi * 180),
                                                Int(camera.eulerAngles.y / Float32.pi * 180),
                                                Int(camera.eulerAngles.z / Float32.pi * 180))
                        self.showInfo += String(format: " | X: %.2f, Y: %.2f, Z: %.2f | ", camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
                        self.showInfo += quality
                        self.frameNum += 1
                        self.lastTime = currentT

//                        self.semaphore.signal()
                    }
                    last_time = currentT
                }
            } else {
                
                if saveDict.isEmpty == false && folderName != nil {
                    
                    self.saveDict["FrameNum"] = frameNum
                    
                    // get save path
                    let path: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    let jsonPath = path.appendingPathComponent(self.folderName!).appendingPathComponent("meta.json")

                    // convert Dictionary to JSON string and save itn
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
                    
                    self.folderName = nil
                    self.frameNum = 0
                    
                } else {
                    let camera = frame.camera
                    let state = camera.trackingState
                    var tracking_quality: Int
                    
                    switch state {
                    case .normal:
                        tracking_quality = 2
                    case .notAvailable:
                        tracking_quality = 0
                    case .limited(_):
                        tracking_quality = 1
                    }
                    
                    let quality: String = String(format: "Q: %d", tracking_quality)
                    
                    showInfo = "Press the button to record >>>\n"
                    
                    if !ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                        showInfo += "Your device does not support Depth\n"
                    }
                    
                    showInfo += String(format: "X: %4d, Y: %4d, Z: %4d",
                                       Int(camera.eulerAngles.x / Float32.pi * 180),
                                       Int(camera.eulerAngles.y / Float32.pi * 180),
                                       Int(camera.eulerAngles.z / Float32.pi * 180))
                    showInfo += String(format: " | X: %.2f, Y: %.2f, Z: %.2f | ", camera.transform.columns.3.x, camera.transform.columns.3.y, camera.transform.columns.3.z)
                    self.showInfo += quality
                }
                
                self.recordFrames = -1
                
            }
        }
        
        func getCurrentTime() -> String {
            let date = Date()
            let calendar = Calendar.current
            let timeString = (
                String(calendar.component(.year, from: date)) +
                String(format: "%02d", calendar.component(.month, from: date)) +
                String(format: "%02d", calendar.component(.day, from: date)) + "-" +
                String(format: "%02d", calendar.component(.hour, from: date)) +
                String(format: "%02d", calendar.component(.minute, from: date)) +
                String(format: "%02d", calendar.component(.second, from: date))
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
        
        
        func arrayFromIntrinsics(_ intrinsics: simd_float3x3) -> [[Float]] {
            var array: [[Float]] = Array(repeating: Array(repeating: Float(), count: 3), count: 3)
            array[0] = [intrinsics.columns.0.x, intrinsics.columns.1.x, intrinsics.columns.2.x]
            array[1] = [intrinsics.columns.0.y, intrinsics.columns.1.y, intrinsics.columns.2.y]
            array[2] = [intrinsics.columns.0.z, intrinsics.columns.1.z, intrinsics.columns.2.z]
            return array
        }
        
        func convertSaveImage(_ pixelBuf: CVPixelBuffer, path: URL) -> Void {
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuf)
            let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
            let uiImage = UIImage(cgImage: cgImage!).jpegData(compressionQuality: 0.70)
            
            // save to file
            do {
                try uiImage?.write(to: path)
            } catch {
                self.showInfo += "Save RBG image failed; "
                print(error)
            }
            
        }
        
        func convertSaveDepthTIFF(_ pixelBuf: CVPixelBuffer, path: URL) -> Void {
            
            let ciImage = CIImage(cvPixelBuffer: pixelBuf)
            
            // save to file
            do {
                try context.writeTIFFRepresentation(of: ciImage, to: path, format: context.workingFormat, colorSpace: context.workingColorSpace!, options: [:])
            } catch {
                self.showInfo += "Save Depth TIFF image failed;"
                print(error)
            }
        }
        
        func convertSaveConfDepth(_ pixelBuf: CVPixelBuffer, path: URL) -> Void {
            
            // return the auxiliary image as a half-float monochrome image instead of the primary image
            let ciImage = CIImage(cvPixelBuffer: pixelBuf, options: [CIImageOption.auxiliaryDepth: true])
            let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
            let uiImage = UIImage(cgImage: cgImage!).pngData()
            
            // save to file
            do {
                try uiImage?.write(to: path)
            } catch {
                self.showInfo += "Save Depth Confidence image failed; "
                print(error)
            }
        }
        
        class DepthData {
            var data: [[Float32]]
            
            init(_ pixelBuf: CVPixelBuffer) {
                let w = CVPixelBufferGetWidth(pixelBuf)  // 256
                let h = CVPixelBufferGetHeight(pixelBuf)  // 192
                self.data = Array(repeating: Array(repeating: Float(-1), count: w), count: h)
            }

            func set(x:Int,y:Int,floatData:Float) {
                data[y][x]=floatData
            }

            func get(x:Int,y:Int) -> Float {
                return data[y][x]
            }
        }
        
        func getDepthDistance(_ pixelBuf: CVPixelBuffer) -> [[Float32]] {
            let depthFloatData = DepthData(pixelBuf)
            
            let depthWidth = CVPixelBufferGetWidth(pixelBuf)
            let depthHeight = CVPixelBufferGetHeight(pixelBuf)
            CVPixelBufferLockBaseAddress(pixelBuf, CVPixelBufferLockFlags(rawValue: 0))
            let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(pixelBuf), to: UnsafeMutablePointer<Float32>.self)
            for y in 0...depthHeight-1 {
                for x in 0...depthWidth-1 {
                    let distanceAtXYPoint = floatBuffer[y*depthWidth+x]
                    depthFloatData.set(x: x, y: y, floatData: distanceAtXYPoint)
                }
            }
            return depthFloatData.data
        }
        
        func saveArray(folderPath: URL, timeStamp: String, array: [[Float32]]) {
            let depthString:String = getStringFrom2DimArray(array: array, height: 192, width: 256)
            // get save path
            let txtPath = folderPath.appendingPathComponent(timeStamp + ".txt")

            // save to file
            do {
                try depthString.write(to: txtPath, atomically: true, encoding: .utf8)
            } catch {
                self.showInfo += "Save TXT failed;"
                print(error)
            }
        }
        
        // Auxiliary function to make String from depth map array
        func getStringFrom2DimArray(array: [[Float32]], height: Int, width: Int) -> String{
            var arrayStr: String = ""
            for y in 0...height-1{
                var lineStr = ""
                for x in 0...width-1{
                    lineStr += String(array[y][x])
                    if x != width-1{
                        lineStr += " "
                    }
                }
                lineStr += "\n"
                arrayStr += lineStr
            }
            return arrayStr
        }
    }
}

struct ContentView: View {
    @State private var showInfo: String = "Press the button to record >>>\n"
    @State private var showImage: String = "play.fill"
    @State private var recordState: Bool = false
    @State private var recordFrames: Int = -1

    let initShow = "Press the button to record >>>\n"

    var body: some View {
        ZStack {
            ARViewContainer(recordState: $recordState, recordFrames: $recordFrames, showInfo: $showInfo, showImage: $showImage)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Text(showInfo)
                        .padding()
                    Spacer()
                    HStack {
                        Button(action: {
                            withAnimation {
                                if showImage == "play.fill" {
                                    showImage = "stop.fill"
                                    recordState = true
                                    
                                } else {
                                    showImage = "play.fill"
                                    showInfo = initShow
                                    recordState = false
                                }
                            }
                        }) {Image(systemName: showImage)}
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            withAnimation {
                                if recordFrames == -1 {
                                    showImage = "stop.fill"
                                    recordFrames = 1500
                                    recordState = true
                                } else {
                                    showImage = "play.fill"
                                    showInfo = initShow
                                    recordState = false
                                }
                            }
                        }) {Image(systemName: showImage)}
                        .foregroundColor(Color.red)
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .background(Color.gray.opacity(0.5))
                Spacer()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.portraitUpsideDown)
    }
}
