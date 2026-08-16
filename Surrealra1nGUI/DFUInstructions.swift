import Cocoa

struct DFUInstructions {
    enum CalloutPosition { case volumeButton, sideButton, top, home }

    let assetName: String
    let imageWidth: CGFloat
    let imageLeading: CGFloat
    let leftCallout: String
    let rightCallout: String
    let leftPosition: CalloutPosition
    let rightPosition: CalloutPosition
    let secondInstruction: String
    let thirdInstruction: String
    let secondStageTerms: [String]
    let thirdStageTerms: [String]

    static func profile(for identifier: String) -> DFUInstructions {
        if identifier.hasPrefix("iPad") {
            return topAndHome(asset: "checkra1n-home-ipad", width: 128, leading: 69)
        }
        if identifier.hasPrefix("iPod") {
            return topAndHome(asset: "checkra1n-home-ipod", width: 92, leading: 92)
        }
        if identifier.hasPrefix("iPhone6,") {
            return topAndHome(asset: "checkra1n-home-iphone", width: 96, leading: 90)
        }
        if identifier.hasPrefix("iPhone7,") {
            return sideAndHome(asset: "checkra1n-home-iphone")
        }
        if identifier == "iPhone8,4" {
            return topAndHome(asset: "checkra1n-home-iphone", width: 96, leading: 90)
        }
        if identifier == "iPhone8,1" || identifier == "iPhone8,2" {
            return sideAndHome(asset: "checkra1n-home-iphone")
        }
        if identifier.hasPrefix("iPhone9,") {
            return sideAndVolume(asset: "checkra1n-home-iphone")
        }

        let homeBodyIdentifiers = ["iPhone10,1", "iPhone10,2", "iPhone10,4", "iPhone10,5", "iPhone12,8"]
        let asset = homeBodyIdentifiers.contains(identifier) ? "checkra1n-home-iphone" : "checkra1n-notched-iphone"
        return sideAndVolume(asset: asset)
    }

    private static func sideAndVolume(asset: String) -> DFUInstructions {
        DFUInstructions(
            assetName: asset, imageWidth: 96, imageLeading: 92,
            leftCallout: "Volume down --", rightCallout: "-- Side button",
            leftPosition: .volumeButton, rightPosition: .sideButton,
            secondInstruction: "Press and hold the Side and Volume down buttons together",
            thirdInstruction: "Release the Side button BUT KEEP HOLDING the Volume down button",
            secondStageTerms: ["side + volume", "power buttons"],
            thirdStageTerms: ["release side", "release power"]
        )
    }

    private static func sideAndHome(asset: String) -> DFUInstructions {
        DFUInstructions(
            assetName: asset, imageWidth: 96, imageLeading: 92,
            leftCallout: "Home button --", rightCallout: "-- Side button",
            leftPosition: .home, rightPosition: .sideButton,
            secondInstruction: "Press and hold the Side and Home buttons together",
            thirdInstruction: "Release the Side button BUT KEEP HOLDING the Home button",
            secondStageTerms: ["power + home", "side + home"],
            thirdStageTerms: ["release power", "release side" ]
        )
    }

    private static func topAndHome(asset: String, width: CGFloat, leading: CGFloat) -> DFUInstructions {
        DFUInstructions(
            assetName: asset, imageWidth: width, imageLeading: leading,
            leftCallout: "Home button --", rightCallout: "-- Top button",
            leftPosition: .home, rightPosition: .top,
            secondInstruction: "Press and hold the Top and Home buttons together",
            thirdInstruction: "Release the Top button BUT KEEP HOLDING the Home button",
            secondStageTerms: ["power + home", "top + home"],
            thirdStageTerms: ["release power", "release top"]
        )
    }
}
