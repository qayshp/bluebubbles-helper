import Foundation
import Darwin
import CoreLocation
import ObjectiveC

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

private func BBObjectClassName(_ object: AnyObject) -> String {
    return String(cString: object_getClassName(object))
}

private func BBMirrorDisplayStyleName(_ style: Mirror.DisplayStyle?) -> String {
    guard let style else {
        return "<nil>"
    }

    switch style {
    case .class:
        return "class"
    case .collection:
        return "collection"
    case .dictionary:
        return "dictionary"
    case .enum:
        return "enum"
    case .optional:
        return "optional"
    case .set:
        return "set"
    case .struct:
        return "struct"
    case .tuple:
        return "tuple"
    default:
        return "\(style)"
    }
}

private func BBMirrorTypeName(_ value: Any) -> String {
    return String(reflecting: type(of: value))
}

private func BBKnownCollectionCount(_ value: Any, mirror: Mirror) -> Int? {
    if let array = value as? [Any] {
        return array.count
    }

    if let array = value as? NSArray {
        return array.count
    }

    if let set = value as? NSSet {
        return set.count
    }

    if let dictionary = value as? NSDictionary {
        return dictionary.count
    }

    switch mirror.displayStyle {
    case .collection, .dictionary, .set:
        return mirror.children.count
    default:
        return nil
    }
}

private func BBScalarMirrorValue(_ value: Any) -> Any? {
    if let string = value as? String {
        return string
    }

    if let number = value as? NSNumber {
        return number
    }

    if let date = value as? NSDate {
        return date.description
    }

    if let bool = value as? Bool {
        return bool
    }

    if let integer = value as? Int {
        return integer
    }

    if let double = value as? Double {
        return double
    }

    if let float = value as? Float {
        return float
    }

    return nil
}

private func BBMirrorChildSummary(_ label: String?, value: Any) -> [String: Any] {
    let mirror = Mirror(reflecting: value)
    var result: [String: Any] = [
        "label": label ?? "<nil>",
        "type": BBMirrorTypeName(value),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
    ]

    if mirror.displayStyle == .class {
        let object = value as AnyObject
        result["object_class"] = BBObjectClassName(object)
    }

    if let count = BBKnownCollectionCount(value, mirror: mirror) {
        result["collection_count"] = count
    }

    if let scalar = BBScalarMirrorValue(value) {
        result["value"] = scalar
    }

    return result
}

private func BBMirrorChildrenSample(_ value: Any, maxChildren: Int) -> [[String: Any]] {
    guard maxChildren > 0 else {
        return []
    }

    var children: [[String: Any]] = []
    var current: Mirror? = Mirror(reflecting: value)

    while let mirror = current, children.count < maxChildren {
        for child in mirror.children {
            if children.count >= maxChildren {
                break
            }

            children.append(BBMirrorChildSummary(child.label, value: child.value))
        }

        current = mirror.superclassMirror
    }

    return children
}

private func BBShallowMirrorSummary(_ object: AnyObject, maxChildren: Int, maxNestedChildren: Int) -> [String: Any] {
    let mirror = Mirror(reflecting: object)
    var children: [[String: Any]] = []
    var current: Mirror? = mirror

    while let currentMirror = current, children.count < maxChildren {
        for child in currentMirror.children {
            if children.count >= maxChildren {
                break
            }

            var childSummary = BBMirrorChildSummary(child.label, value: child.value)
            let nested = BBMirrorChildrenSample(child.value, maxChildren: maxNestedChildren)
            if !nested.isEmpty {
                childSummary["children_sample"] = nested
            }

            children.append(childSummary)
        }

        current = currentMirror.superclassMirror
    }

    return [
        "mirror_available": true,
        "object_class": BBObjectClassName(object),
        "type": String(reflecting: type(of: object)),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
        "children_sampled": children.count,
        "max_children": maxChildren,
        "max_nested_children": maxNestedChildren,
        "children": children,
    ]
}

private func BBIvarMetadata(_ startingClass: AnyClass?) -> [[String: Any]] {
    var result: [[String: Any]] = []
    var seen = Set<String>()
    var currentClass: AnyClass? = startingClass

    while let klass = currentClass {
        var count: UInt32 = 0
        if let ivars = class_copyIvarList(klass, &count) {
            defer { free(ivars) }
            for index in 0..<Int(count) {
                let ivar = ivars[index]
                let name = ivar_getName(ivar).map { String(cString: $0) } ?? ""
                guard !name.isEmpty, !seen.contains(name) else {
                    continue
                }

                seen.insert(name)
                result.append([
                    "name": name,
                    "encoding": ivar_getTypeEncoding(ivar).map { String(cString: $0) } ?? "",
                    "offset": ivar_getOffset(ivar),
                    "declaring_class": NSStringFromClass(klass),
                ])
            }
        }

        currentClass = class_getSuperclass(klass)
    }

    return result
}

private func BBIvar(_ startingClass: AnyClass?, named name: String) -> Ivar? {
    var currentClass: AnyClass? = startingClass
    while let klass = currentClass {
        if let ivar = class_getInstanceVariable(klass, name) {
            return ivar
        }

        currentClass = class_getSuperclass(klass)
    }

    return nil
}

private func BBObjectIvar(_ object: AnyObject, named name: String) -> AnyObject? {
    guard let ivar = BBIvar(object_getClass(object), named: name) else {
        return nil
    }

    return object_getIvar(object, ivar) as AnyObject?
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

    let managerClass: AnyClass? = object_getClass(manager)
    let managerIvars = BBIvarMetadata(managerClass)
    let managerIvarNames = managerIvars.compactMap { $0["name"] as? String }
    let dataManagerObject = BBObjectIvar(manager, named: "dataManager")
    let dataManagerClass: AnyClass? = dataManagerObject.flatMap { object_getClass($0) }
    let dataManagerIvars = BBIvarMetadata(dataManagerClass)
    let dataManagerIvarNames = dataManagerIvars.compactMap { $0["name"] as? String }
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

    let targetFieldMetadata = targetFields.map { field -> [String: Any] in
        if let metadata = dataManagerIvars.first(where: { ($0["name"] as? String) == field }) {
            return [
                "name": field,
                "present": true,
                "encoding": metadata["encoding"] ?? "",
                "offset": metadata["offset"] ?? 0,
                "declaring_class": metadata["declaring_class"] ?? "",
            ]
        }

        return [
            "name": field,
            "present": false,
        ]
    }

    return [
        "fmip_manager_present": true,
        "manager_class": BBObjectClassName(manager),
        "manager_runtime_class": managerClass.map { NSStringFromClass($0) } ?? "",
        "manager_ivar_count": managerIvars.count,
        "manager_ivar_names_sample": Array(managerIvarNames.prefix(40)),
        "data_manager_ivar_declared": managerIvarNames.contains("dataManager"),
        "data_manager_present": dataManagerObject != nil,
        "data_manager_class": dataManagerObject.map { BBObjectClassName($0) } ?? "",
        "data_manager_runtime_class": dataManagerClass.map { NSStringFromClass($0) } ?? "",
        "data_manager_ivar_count": dataManagerIvars.count,
        "data_manager_ivar_names_sample": Array(dataManagerIvarNames.prefix(80)),
        "target_field_metadata": targetFieldMetadata,
        "field_summaries": [:],
        "missing_fields": targetFieldMetadata.compactMap { (($0["present"] as? Bool) == false) ? ($0["name"] as? String) : nil },
        "snapshot_mode": "objc_runtime_ivar_metadata_retained_fmip_manager_data_manager",
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

@_cdecl("BlueBubblesFindMyCopySwiftMirrorSummary")
public func BlueBubblesFindMyCopySwiftMirrorSummary(_ objectPointer: UnsafeMutableRawPointer?, _ maxChildren: Int32, _ maxNestedChildren: Int32) -> UnsafeMutableRawPointer? {
    guard let objectPointer else {
        return Unmanaged.passRetained([
            "mirror_available": false,
            "error": "missing object pointer",
        ] as NSDictionary).toOpaque()
    }

    let object = Unmanaged<AnyObject>.fromOpaque(objectPointer).takeUnretainedValue()
    let boundedMaxChildren = max(0, min(Int(maxChildren), 48))
    let boundedMaxNestedChildren = max(0, min(Int(maxNestedChildren), 12))
    let summary = BBShallowMirrorSummary(object, maxChildren: boundedMaxChildren, maxNestedChildren: boundedMaxNestedChildren)

    return Unmanaged.passRetained(summary as NSDictionary).toOpaque()
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
