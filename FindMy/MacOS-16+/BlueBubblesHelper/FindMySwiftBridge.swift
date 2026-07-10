import Foundation
import Darwin
import CoreLocation

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
private func FMIPManagerDevices(_ manager: AnyObject) -> [Any]

private var retainedFMIPManager: AnyObject?

private func BBTruncatedDescription(_ value: Any, limit: Int = 220) -> String {
    let description = String(describing: value)
    if description.count <= limit {
        return description
    }
    return String(description.prefix(limit)) + "..."
}

private func BBMirrorChildrenByLabel(_ value: Any) -> [String: Any] {
    var result: [String: Any] = [:]
    var current: Mirror? = Mirror(reflecting: value)
    while let mirror = current {
        for child in mirror.children {
            guard let label = child.label, result[label] == nil else {
                continue
            }
            result[label] = child.value
        }
        current = mirror.superclassMirror
    }
    return result
}

private func BBLocationSummary(_ value: Any) -> [String: Any]? {
    if let location = value as? CLLocation {
        return [
            "class": NSStringFromClass(type(of: location)),
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "vertical_accuracy": location.verticalAccuracy,
            "timestamp": location.timestamp.description,
        ]
    }

    if let object = value as? NSObject, object.isKind(of: CLLocation.self),
       let location = object as? CLLocation {
        return [
            "class": NSStringFromClass(type(of: location)),
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "vertical_accuracy": location.verticalAccuracy,
            "timestamp": location.timestamp.description,
        ]
    }

    return nil
}

private func BBLocationSignalSummary(_ value: Any, depth: Int = 0) -> [String: Any] {
    var signal: [String: Any] = [:]
    if let location = BBLocationSummary(value) {
        signal["direct_location"] = location
        return signal
    }

    guard depth < 2 else {
        return signal
    }

    let children = BBMirrorChildrenByLabel(value)
    var labels: [String] = []
    var childLocations: [String: Any] = [:]
    for (label, child) in children {
        let lower = label.lowercased()
        if lower.contains("location") || lower.contains("coordinate") {
            labels.append(label)
            if let location = BBLocationSummary(child) {
                childLocations[label] = location
            } else if childLocations.count < 6 {
                childLocations[label] = BBValueSummary(child, depth: depth + 1, sampleLimit: 2)
            }
        }
        if labels.count >= 12 {
            break
        }
    }

    if !labels.isEmpty {
        signal["location_like_child_labels"] = labels.sorted()
    }
    if !childLocations.isEmpty {
        signal["location_like_child_summaries"] = childLocations
    }

    return signal
}

private func BBValueSummary(_ value: Any, depth: Int = 0, sampleLimit: Int = 5) -> [String: Any] {
    let mirror = Mirror(reflecting: value)
    var result: [String: Any] = [
        "swift_type": String(reflecting: type(of: value)),
        "description": BBTruncatedDescription(value),
    ]

    if let displayStyle = mirror.displayStyle {
        result["display_style"] = String(describing: displayStyle)
    }

    if mirror.displayStyle == .optional {
        if let child = mirror.children.first {
            result["optional_is_some"] = true
            result["wrapped"] = BBValueSummary(child.value, depth: depth + 1, sampleLimit: sampleLimit)
        } else {
            result["optional_is_some"] = false
        }
        return result
    }

    if let location = BBLocationSummary(value) {
        result["location"] = location
        return result
    }

    if let string = value as? String {
        result["value"] = string
        return result
    }

    if let number = value as? NSNumber {
        result["value"] = number
        return result
    }

    if let date = value as? Date {
        result["value"] = date.description
        return result
    }

    if let object = value as? NSObject {
        result["object_class"] = NSStringFromClass(type(of: object))
    }

    if let array = value as? NSArray {
        result["count"] = array.count
        var samples: [[String: Any]] = []
        for index in 0..<min(array.count, sampleLimit) {
            let element = array[index]
            var sample = BBValueSummary(element, depth: depth + 1, sampleLimit: 2)
            let signal = BBLocationSignalSummary(element, depth: depth + 1)
            if !signal.isEmpty {
                sample["location_signal"] = signal
            }
            samples.append(sample)
        }
        result["sample"] = samples
        return result
    }

    if let set = value as? NSSet {
        result["count"] = set.count
        var samples: [[String: Any]] = []
        for element in set.allObjects.prefix(sampleLimit) {
            var sample = BBValueSummary(element, depth: depth + 1, sampleLimit: 2)
            let signal = BBLocationSignalSummary(element, depth: depth + 1)
            if !signal.isEmpty {
                sample["location_signal"] = signal
            }
            samples.append(sample)
        }
        result["sample"] = samples
        return result
    }

    if let dictionary = value as? NSDictionary {
        result["count"] = dictionary.count
        var samples: [[String: Any]] = []
        var index = 0
        for key in dictionary.allKeys {
            guard index < sampleLimit else {
                break
            }
            let dictionaryValue = dictionary[key] as Any
            var sample: [String: Any] = [
                "key": BBTruncatedDescription(key),
                "key_summary": BBValueSummary(key, depth: depth + 1, sampleLimit: 2),
                "value_summary": BBValueSummary(dictionaryValue, depth: depth + 1, sampleLimit: 2),
            ]
            let signal = BBLocationSignalSummary(dictionaryValue, depth: depth + 1)
            if !signal.isEmpty {
                sample["value_location_signal"] = signal
            }
            samples.append(sample)
            index += 1
        }
        result["sample"] = samples
        return result
    }

    if mirror.displayStyle == .collection || mirror.displayStyle == .set {
        let children = Array(mirror.children)
        result["count"] = children.count
        if depth < 2 {
            var samples: [[String: Any]] = []
            for child in children.prefix(sampleLimit) {
                var sample = BBValueSummary(child.value, depth: depth + 1, sampleLimit: 2)
                let signal = BBLocationSignalSummary(child.value, depth: depth + 1)
                if !signal.isEmpty {
                    sample["location_signal"] = signal
                }
                samples.append(sample)
            }
            result["sample"] = samples
        }
        return result
    }

    if mirror.displayStyle == .dictionary {
        let children = Array(mirror.children)
        result["count"] = children.count
        if depth < 2 {
            var samples: [[String: Any]] = []
            for child in children.prefix(sampleLimit) {
                let pairChildren = Array(Mirror(reflecting: child.value).children)
                var sample: [String: Any] = [:]
                for pairChild in pairChildren {
                    guard let label = pairChild.label else {
                        continue
                    }
                    sample[label] = BBValueSummary(pairChild.value, depth: depth + 1, sampleLimit: 2)
                    if label == "value" {
                        let signal = BBLocationSignalSummary(pairChild.value, depth: depth + 1)
                        if !signal.isEmpty {
                            sample["value_location_signal"] = signal
                        }
                    }
                }
                samples.append(sample)
            }
            result["sample"] = samples
        }
        return result
    }

    if mirror.displayStyle == .class || mirror.displayStyle == .struct {
        let children = BBMirrorChildrenByLabel(value)
        result["child_count"] = children.count
        result["child_labels_sample"] = Array(children.keys.sorted().prefix(16))
        let signal = BBLocationSignalSummary(value, depth: depth)
        if !signal.isEmpty {
            result["location_signal"] = signal
        }
    }

    return result
}

private func BBFMIPDataManagerSnapshot() -> [String: Any] {
    guard let manager = retainedFMIPManager else {
        return [
            "fmip_manager_present": false,
            "error": "missing retained FMIPManager",
        ]
    }

    let managerChildren = BBMirrorChildrenByLabel(manager)
    guard let dataManager = managerChildren["dataManager"] else {
        return [
            "fmip_manager_present": true,
            "manager_class": NSStringFromClass(type(of: manager)),
            "manager_child_labels_sample": Array(managerChildren.keys.sorted().prefix(24)),
            "data_manager_present": false,
        ]
    }

    let dataManagerChildren = BBMirrorChildrenByLabel(dataManager)
    let targetFields = [
        "devices",
        "crowdSourcedLocations",
        "crowdSourcedOriginalLocations",
        "deviceConnectedStates",
        "safeLocations",
        "safeLocationsMapping",
        "owner",
        "familyMembers",
    ]

    var fields: [String: Any] = [:]
    var missingFields: [String] = []
    for field in targetFields {
        guard let value = dataManagerChildren[field] else {
            missingFields.append(field)
            continue
        }
        var summary = BBValueSummary(value, sampleLimit: 5)
        let signal = BBLocationSignalSummary(value)
        if !signal.isEmpty {
            summary["location_signal"] = signal
        }
        fields[field] = summary
    }

    return [
        "fmip_manager_present": true,
        "manager_class": NSStringFromClass(type(of: manager)),
        "manager_child_labels_sample": Array(managerChildren.keys.sorted().prefix(24)),
        "data_manager_present": true,
        "data_manager_type": String(reflecting: type(of: dataManager)),
        "data_manager_child_labels_sample": Array(dataManagerChildren.keys.sorted().prefix(40)),
        "field_summaries": fields,
        "missing_fields": missingFields,
        "snapshot_mode": "swift_mirror_retained_fmip_manager_data_manager",
    ]
}

@_cdecl("BlueBubblesFindMySwiftProbe")
public func BlueBubblesFindMySwiftProbe() -> UnsafeMutableRawPointer? {
    let classNames = [
        "FMIPCore.FMIPManager",
        "FMIPCore.FMIPDevice",
        "FMIPCore.FMIPItem",
        "FindMyCore.DeviceLocationEntity",
        "FindMyCore.DeviceLocationEntityQuery",
        "FindMyCore.PublishedLocation",
        "FindMyCore.Location",
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
        "device_classes": [],
        "device_summaries": [],
        "snapshot_mode": "count_only",
        "devices": [],
    ]

    return Unmanaged.passRetained(result as NSDictionary).toOpaque()
}

@_cdecl("BlueBubblesFindMyCopyFMIPDataManagerSnapshot")
public func BlueBubblesFindMyCopyFMIPDataManagerSnapshot() -> UnsafeMutableRawPointer? {
    let snapshot = BBFMIPDataManagerSnapshot()
    return Unmanaged.passRetained(snapshot as NSDictionary).toOpaque()
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
