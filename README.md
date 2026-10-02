# PhotoLab

A small SwiftUI image editor and comparison demo for iOS 17 or later.

Open `PhotoLab.xcodeproj` in Xcode, choose an iPhone or iPad simulator or device, set your development team if running on a device, and run. Choose Photo A to edit. Add Photo B to compare. On a device with a camera, you can capture Photo A through `UIImagePickerController`. Export writes a JPEG to a temporary file and exposes it through the share sheet.

The app uses PhotosPicker with a file Transferable, Image I/O thumbnails, Vision saliency, horizon detection, OCR, foreground masks, feature prints, and translation registration. Core Image renders crop, rotation, and subject background effects. The source file is kept unchanged. PhotoKit `PHAsset` access is unnecessary because the app only uses the photos a person selects.

Vision suggestions can be wrong. Photo A and Photo B align best when they contain nearly the same scene. A foreground effect applies only when Vision finds a subject. Export decodes the selected image at its source dimensions, so very large photos may use substantial memory. The demo does not persist editing settings between launches.

The included Swift Testing check covers image previews, cropping, comparison fallback, and JPEG export in iOS Simulator. The Vision model check is device-only because the available simulator failed to create an Espresso model context. Run the app on an iPhone to validate similarity, subject masking, saliency, horizon detection, and OCR with real photos. JPEG export does not retain the source's HDR or metadata.
