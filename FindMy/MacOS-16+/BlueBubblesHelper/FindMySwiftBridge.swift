import Foundation
import Darwin

@_silgen_name("$s8FMIPCore24FMIPManagerConfigurationC7defaultACvgZ")
private func FMIPManagerConfigurationDefault() -> AnyObject

@_silgen_name("$s8FMIPCore11FMIPManagerC13configuration12ownerSessionAcA0B13ConfigurationC_So07SPOwnerE0CtcfC")
private func FMIPManagerCreate(_ configuration: AnyObject, _ ownerSession: AnyObject) -> AnyObject

@_silgen_name("$s8FMIPCore11FMIPManagerC10initializeyyF")
private func FMIPManagerInitialize(_ manager: AnyObject)

@_silgen_name("$s8FMIPCore11FMIPManagerC15startRefreshingyyF")
private func FMIPManagerStartRefreshing(_ manager: AnyObject)

@_silgen_name("$s8FMIPCore11FMIPManagerC7refreshyyF")
private func FMIPManagerRefresh(_ manager: AnyObject)

@_silgen_name("$s8FMIPCore11FMIPManagerC7devicesSayAA10FMIPDeviceVGvg")
private func FMIPManagerDevices(_ manager: AnyObject) -> [AnyObject]

private var retainedFMIPManager: AnyObject?

@_cdecl("BlueBubblesFindMySwiftProbe")
public func BlueBubblesFindMySwiftProbe() -> UnsafeMutableRawPointer? {
    let classNames = [
        "FMIPCore.FMIPManager",
        "FMIPCore.FMIPDevice",
        "FMIPCore.FMIPItem",
        "FindMy.FMDevicesProvider",
        "FindMy.FMDevicesListDataSource",
        "FindMy.FMItemsListDataSource",
        "FindMyUICore.Repository",
        "FindMyUICore.SessionLive",
        "SPOwnerSession",
    ]

    var availability: [String: Bool] = [:]
    for className in classNames {
        availability[className] = NSClassFromString(className) != nil
    }

    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    let symbolNames = [
        "FMIPManager.devices": "$s8FMIPCore11FMIPManagerC7devicesSayAA10FMIPDeviceVGvg",
        "FMIPManager.items": "$s8FMIPCore11FMIPManagerC5itemsSayAA8FMIPItemVGvg",
        "FMIPManager.refresh": "$s8FMIPCore11FMIPManagerC7refreshyyF",
        "FMIPManager.startRefreshing": "$s8FMIPCore11FMIPManagerC15startRefreshingyyF",
        "FMIPManager.initialize": "$s8FMIPCore11FMIPManagerC10initializeyyF",
        "FMIPManagerConfiguration.default": "$s8FMIPCore24FMIPManagerConfigurationC7defaultACvgZ",
        "FMIPManager.init(configuration:ownerSession:)": "$s8FMIPCore11FMIPManagerC13configuration12ownerSessionAcA0B13ConfigurationC_So07SPOwnerE0CtcfC",
    ]

    var symbols: [String: Bool] = [:]
    for (label, symbolName) in symbolNames {
        symbols[label] = dlsym(rtldDefault, symbolName) != nil
    }

    let result: [String: Any] = [
        "swift_bridge_loaded": true,
        "swift_runtime_class_availability": availability,
        "swift_symbol_availability": symbols,
    ]

    return Unmanaged.passRetained(result as NSDictionary).toOpaque()
}

@_cdecl("BlueBubblesFindMyCopyFMIPManagerDevices")
public func BlueBubblesFindMyCopyFMIPManagerDevices() -> UnsafeMutableRawPointer? {
    guard let manager = retainedFMIPManager else {
        return Unmanaged.passRetained([
            "fmip_manager_present": false,
            "devices": [],
        ] as NSDictionary).toOpaque()
    }

    let devices = FMIPManagerDevices(manager)
    let result: [String: Any] = [
        "fmip_manager_present": true,
        "manager_class": NSStringFromClass(type(of: manager)),
        "device_count": devices.count,
        "device_classes": devices.map { NSStringFromClass(type(of: $0)) },
        "devices": devices,
    ]

    return Unmanaged.passRetained(result as NSDictionary).toOpaque()
}

@_cdecl("BlueBubblesFindMyStartFMIPManager")
public func BlueBubblesFindMyStartFMIPManager(_ ownerSessionPointer: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let ownerSessionPointer else {
        return Unmanaged.passRetained([
            "fmip_manager_started": false,
            "error": "missing owner session",
        ] as NSDictionary).toOpaque()
    }

    let ownerSession = Unmanaged<AnyObject>.fromOpaque(ownerSessionPointer).takeUnretainedValue()
    let configuration = FMIPManagerConfigurationDefault()
    let manager = FMIPManagerCreate(configuration, ownerSession)
    retainedFMIPManager = manager

    FMIPManagerInitialize(manager)
    FMIPManagerStartRefreshing(manager)
    FMIPManagerRefresh(manager)

    let result: [String: Any] = [
        "fmip_manager_started": true,
        "manager_class": NSStringFromClass(type(of: manager)),
        "configuration_class": NSStringFromClass(type(of: configuration)),
        "owner_session_class": NSStringFromClass(type(of: ownerSession)),
    ]

    return Unmanaged.passRetained(result as NSDictionary).toOpaque()
}
