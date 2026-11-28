import UIKit
import ImageIO

@MainActor final class FinamiImageCache {
    static let shared = FinamiImageCache()
    private let cache = NSCache<NSData, UIImage>()
    private init() { cache.totalCostLimit = 12 * 1024 * 1024; cache.countLimit = 24 }
    func image(_ data: Data) -> UIImage? {
        let key = data as NSData
        if let image = cache.object(forKey:key) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:800] as CFDictionary) else { return nil }
        let image = UIImage(cgImage:decoded)
        cache.setObject(image,forKey:key,cost:decoded.bytesPerRow * decoded.height + data.count)
        return image
    }
}

// ImageIO decodes only a bounded thumbnail instead of allocating the original full-resolution bitmap.
func finamiThumbnailJPEG(_ data: Data, maxPixels: Int) -> Data? {
    guard data.count <= 25_000_000, let source = CGImageSourceCreateWithData(data as CFData,nil),
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:maxPixels] as CFDictionary) else { return nil }
    let result = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(result as CFMutableData,"public.jpeg" as CFString,1,nil) else { return nil }
    CGImageDestinationAddImage(destination,thumbnail,[kCGImageDestinationLossyCompressionQuality:0.75] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return result as Data
}
