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

private func BBShallowAnyMirrorSummary(_ value: Any, maxChildren: Int, maxNestedChildren: Int) -> [String: Any] {
    let mirror = Mirror(reflecting: value)
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

    var result: [String: Any] = [
        "type": BBMirrorTypeName(value),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
        "children_sampled": children.count,
        "max_children": maxChildren,
        "max_nested_children": maxNestedChildren,
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

    if !children.isEmpty {
        result["children"] = children
    }

    return result
}

private func BBMirrorChildValue(_ value: Any, label targetLabel: String) -> Any? {
    var current: Mirror? = Mirror(reflecting: value)

    while let mirror = current {
        for child in mirror.children where child.label == targetLabel {
            return child.value
        }

        current = mirror.superclassMirror
    }

    return nil
}

private func BBUnwrappedOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else {
        return value
    }

    return mirror.children.first?.value
}

private func BBDevicesDataSourceFocusedSummary(_ dataSource: AnyObject, maxSections: Int, maxRowsPerSection: Int, maxChildren: Int, maxNestedChildren: Int) -> [String: Any] {
    var result: [String: Any] = [
        "focused_summary_available": true,
        "object_class": BBObjectClassName(dataSource),
        "type": String(reflecting: type(of: dataSource)),
        "max_sections": maxSections,
        "max_rows_per_section": maxRowsPerSection,
        "max_children": maxChildren,
        "max_nested_children": maxNestedChildren,
    ]

    if let cellsValue = BBMirrorChildValue(dataSource, label: "cellsViewModel") {
        let cellsMirror = Mirror(reflecting: cellsValue)
        var sections: [[String: Any]] = []
        var sectionIndex = 0
        for sectionChild in cellsMirror.children {
            if sections.count >= maxSections {
                break
            }

            let sectionValue = sectionChild.value
            let sectionMirror = Mirror(reflecting: sectionValue)
            var rows: [[String: Any]] = []
            var rowIndex = 0
            for rowChild in sectionMirror.children {
                if rows.count >= maxRowsPerSection {
                    break
                }

                rows.append([
                    "row_index": rowIndex,
                    "summary": BBShallowAnyMirrorSummary(rowChild.value, maxChildren: maxChildren, maxNestedChildren: maxNestedChildren),
                ])
                rowIndex += 1
            }

            sections.append([
                "section_index": sectionIndex,
                "section_type": BBMirrorTypeName(sectionValue),
                "section_display_style": BBMirrorDisplayStyleName(sectionMirror.displayStyle),
                "row_count": BBKnownCollectionCount(sectionValue, mirror: sectionMirror) ?? rowIndex,
                "rows_sample": rows,
            ])
            sectionIndex += 1
        }

        result["cellsViewModel"] = [
            "type": BBMirrorTypeName(cellsValue),
            "display_style": BBMirrorDisplayStyleName(cellsMirror.displayStyle),
            "section_count": BBKnownCollectionCount(cellsValue, mirror: cellsMirror) ?? sectionIndex,
            "sections_sample": sections,
        ]
    } else {
        result["cellsViewModel"] = [
            "present": false,
        ]
    }

    let providerLabels = [
        "conditionProvider",
        "devicesProvider",
        "etaProvider",
        "locationProvider",
        "peopleProvider",
        "selectionController",
        "productAssetProvider",
        "isRefreshing",
    ]
    if let mediatorValue = BBMirrorChildValue(dataSource, label: "mediator") {
        var providerSummaries: [String: Any] = [:]
        for providerLabel in providerLabels {
            if let providerValue = BBMirrorChildValue(mediatorValue, label: providerLabel) {
                providerSummaries[providerLabel] = BBShallowAnyMirrorSummary(providerValue, maxChildren: maxChildren, maxNestedChildren: maxNestedChildren)
            } else {
                providerSummaries[providerLabel] = ["present": false]
            }
        }

        result["mediator"] = [
            "summary": BBShallowAnyMirrorSummary(mediatorValue, maxChildren: maxChildren, maxNestedChildren: maxNestedChildren),
            "providers": providerSummaries,
        ]
    } else {
        result["mediator"] = [
            "present": false,
        ]
    }

    var subscriptionSummaries: [String: Any] = [:]
    for subscriptionLabel in ["deviceSubscription", "locationSubscription", "itemAger"] {
        if let subscriptionValue = BBMirrorChildValue(dataSource, label: subscriptionLabel),
           let unwrapped = BBUnwrappedOptional(subscriptionValue) {
            subscriptionSummaries[subscriptionLabel] = BBShallowAnyMirrorSummary(unwrapped, maxChildren: maxChildren, maxNestedChildren: maxNestedChildren)
        } else {
            subscriptionSummaries[subscriptionLabel] = ["present": false]
        }
    }
    result["subscriptions"] = subscriptionSummaries

    return result
}

private func BBFMIPLocationSummary(_ value: Any) -> [String: Any]? {
    let unwrapped = BBUnwrappedOptional(value) ?? value
    let typeName = BBMirrorTypeName(unwrapped)
    guard typeName == "FMIPCore.FMIPLocation" || typeName.hasSuffix(".FMIPLocation") else {
        return nil
    }

    var result: [String: Any] = [
        "type": typeName,
    ]

    for label in ["location", "floor", "isInaccurate", "isLocationFinished", "isOld", "locationType"] {
        guard let child = BBMirrorChildValue(unwrapped, label: label) else {
            continue
        }

        if label == "location" {
            if let childUnwrapped = BBUnwrappedOptional(child),
               let location = BBLocationSummary(childUnwrapped) {
                result[label] = location
            } else {
                result[label] = BBCompactShapeSummary(child, maxChildLabels: 8)
            }
            continue
        }

        result[label] = BBCompactShapeSummary(child, maxChildLabels: 8)
    }

    return result
}

private func BBCompactScalarLikeValue(_ value: Any?) -> Any? {
    guard let value, let unwrapped = BBUnwrappedOptional(value) else {
        return nil
    }

    if let scalar = BBScalarMirrorValue(unwrapped) {
        return scalar
    }

    if let location = BBLocationSummary(unwrapped) {
        return location
    }

    if let fmipLocation = BBFMIPLocationSummary(unwrapped) {
        return fmipLocation
    }

    let mirror = Mirror(reflecting: unwrapped)
    if mirror.displayStyle == .enum {
        return [
            "type": BBMirrorTypeName(unwrapped),
            "display_style": "enum",
        ]
    }

    return nil
}

private func BBCompactAddressSummary(_ value: Any?) -> [String: Any]? {
    guard let value, let unwrapped = BBUnwrappedOptional(value) else {
        return nil
    }

    var result: [String: Any] = [
        "type": BBMirrorTypeName(unwrapped),
    ]
    for label in ["label", "mapItemFormattedAddress", "mediumAddressModern", "largeAddressModern", "locality", "administrativeArea", "countryCode"] {
        if let child = BBMirrorChildValue(unwrapped, label: label),
           let scalar = BBCompactScalarLikeValue(child) {
            result[label] = scalar
        }
    }

    return result.count > 1 ? result : nil
}

private func BBFMIPDeviceCompactRecord(_ value: Any, index: Int) -> [String: Any] {
    var result: [String: Any] = [
        "index": index,
        "type": BBMirrorTypeName(value),
    ]

    for label in ["identifier", "name", "displayName", "model", "rawDeviceModel", "systemVersion", "batteryLevel", "batteryStatus", "deviceConnectedState", "discoveryIdentifier", "baIdentifier", "beaconType", "category"] {
        if let scalar = BBCompactScalarLikeValue(BBMirrorChildValue(value, label: label)) {
            result[label] = scalar
        }
    }

    if let address = BBCompactAddressSummary(BBMirrorChildValue(value, label: "address")) {
        result["address"] = address
    }

    for label in ["location", "crowdSourcedLocation"] {
        if let child = BBMirrorChildValue(value, label: label) {
            result["\(label)Present"] = BBUnwrappedOptional(child) != nil
            if let scalar = BBCompactScalarLikeValue(child) {
                result[label] = scalar
            }
        }
    }

    if let historicalLocations = BBMirrorChildValue(value, label: "historicalLocations") {
        let unwrapped = BBUnwrappedOptional(historicalLocations)
        result["historicalLocationsPresent"] = unwrapped != nil
        if let unwrapped {
            let mirror = Mirror(reflecting: unwrapped)
            result["historicalLocationsCount"] = BBKnownCollectionCount(unwrapped, mirror: mirror)
        }
    }

    if let safeLocations = BBMirrorChildValue(value, label: "safeLocations") {
        let mirror = Mirror(reflecting: safeLocations)
        result["safeLocationsCount"] = BBKnownCollectionCount(safeLocations, mirror: mirror)
    }

    return result
}

private func BBFMIPDataManagerDevicesCompact(_ dataManager: Any, maxDevices: Int) -> [String: Any] {
    guard let devicesValue = BBMirrorChildValue(dataManager, label: "devices"),
          let devices = BBUnwrappedOptional(devicesValue) else {
        return [
            "present": false,
        ]
    }

    let mirror = Mirror(reflecting: devices)
    var records: [[String: Any]] = []
    var index = 0
    for child in mirror.children {
        if records.count >= maxDevices {
            break
        }

        records.append(BBFMIPDeviceCompactRecord(child.value, index: index))
        index += 1
    }

    return [
        "present": true,
        "type": BBMirrorTypeName(devices),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
        "device_count": BBKnownCollectionCount(devices, mirror: mirror) ?? index,
        "devices_returned": records.count,
        "devices": records,
    ]
}

private func BBCollectionCountOnly(_ value: Any?, label: String) -> [String: Any] {
    guard let value, let unwrapped = BBUnwrappedOptional(value) else {
        return [
            "label": label,
            "present": false,
        ]
    }

    let mirror = Mirror(reflecting: unwrapped)
    var result: [String: Any] = [
        "label": label,
        "present": true,
        "type": BBMirrorTypeName(unwrapped),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
    ]

    if let count = BBKnownCollectionCount(unwrapped, mirror: mirror) {
        result["count"] = count
    }

    return result
}

private func BBCompactShapeSummary(_ value: Any, maxChildLabels: Int = 24) -> [String: Any] {
    let mirror = Mirror(reflecting: value)
    var result: [String: Any] = [
        "type": BBMirrorTypeName(value),
        "display_style": BBMirrorDisplayStyleName(mirror.displayStyle),
    ]

    if mirror.displayStyle == .optional {
        result["optional_is_some"] = mirror.children.first != nil
        if let wrapped = BBUnwrappedOptional(value) {
            result["wrapped"] = BBCompactShapeSummary(wrapped, maxChildLabels: maxChildLabels)
        }
        return result
    }

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

    if let location = BBLocationSummary(value) {
        result["direct_location"] = location
    }

    if let fmipLocation = BBFMIPLocationSummary(value) {
        result["fmip_location"] = fmipLocation
    }

    let children = BBMirrorChildrenByLabel(value)
    if !children.isEmpty {
        result["child_count"] = children.count
        result["child_labels_sample"] = Array(children.keys.sorted().prefix(maxChildLabels))
    }

    return result
}

private func BBCompactFieldSummary(_ value: Any?, label: String, maxChildLabels: Int = 24) -> [String: Any] {
    guard let value else {
        return [
            "label": label,
            "present": false,
        ]
    }

    let declaredMirror = Mirror(reflecting: value)
    var result: [String: Any] = [
        "label": label,
        "present": true,
        "declared_type": BBMirrorTypeName(value),
        "declared_display_style": BBMirrorDisplayStyleName(declaredMirror.displayStyle),
    ]

    if declaredMirror.displayStyle == .optional {
        result["optional_is_some"] = declaredMirror.children.first != nil
    }

    if let unwrapped = BBUnwrappedOptional(value) {
        result["shape"] = BBCompactShapeSummary(unwrapped, maxChildLabels: maxChildLabels)
    }

    return result
}

private func BBCompactLocationSignal(_ value: Any, maxSignals: Int = 8) -> [String: Any] {
    if let location = BBLocationSummary(value) {
        return [
            "direct_location": location,
        ]
    }

    let children = BBMirrorChildrenByLabel(value)
    var labels: [String] = []
    var summaries: [String: Any] = [:]
    for label in children.keys.sorted() {
        let lower = label.lowercased()
        guard lower.contains("location") || lower.contains("coordinate") else {
            continue
        }
        labels.append(label)
        if let child = children[label] {
            if let fmipLocation = BBFMIPLocationSummary(child) {
                summaries[label] = fmipLocation
            } else if let unwrapped = BBUnwrappedOptional(child), let location = BBLocationSummary(unwrapped) {
                summaries[label] = location
            } else {
                summaries[label] = BBCompactShapeSummary(child, maxChildLabels: 12)
            }
        }
        if labels.count >= maxSignals {
            break
        }
    }

    if labels.isEmpty {
        return [:]
    }

    return [
        "location_like_child_labels": labels,
        "location_like_child_summaries": summaries,
    ]
}

private func BBCompactSelectedFields(_ value: Any, labels: [String], maxChildLabels: Int = 16) -> [String: Any] {
    var result: [String: Any] = [:]
    for label in labels {
        if let child = BBMirrorChildValue(value, label: label) {
            result[label] = BBCompactFieldSummary(child, label: label, maxChildLabels: maxChildLabels)
        }
    }
    return result
}

private func BBCompactCollectionSummary(_ value: Any?, label: String, maxElements: Int, selectedElementFields: [String] = []) -> [String: Any] {
    var result = BBCompactFieldSummary(value, label: label, maxChildLabels: 18)
    guard let value, let unwrapped = BBUnwrappedOptional(value) else {
        return result
    }

    let mirror = Mirror(reflecting: unwrapped)
    result["collection_type"] = BBMirrorTypeName(unwrapped)
    result["collection_display_style"] = BBMirrorDisplayStyleName(mirror.displayStyle)
    result["collection_count"] = BBKnownCollectionCount(unwrapped, mirror: mirror)

    var samples: [[String: Any]] = []
    var index = 0
    for child in mirror.children {
        if samples.count >= maxElements {
            break
        }

        var sample: [String: Any] = [
            "index": index,
            "shape": BBCompactShapeSummary(child.value, maxChildLabels: 20),
        ]

        let selectedFields = BBCompactSelectedFields(child.value, labels: selectedElementFields, maxChildLabels: 12)
        if !selectedFields.isEmpty {
            sample["selected_fields"] = selectedFields
        }

        let signal = BBCompactLocationSignal(child.value)
        if !signal.isEmpty {
            sample["location_signal"] = signal
        }

        samples.append(sample)
        index += 1
    }

    result["sample_count"] = samples.count
    result["sample"] = samples
    return result
}

private func BBDevicesProviderFocusedSummary(_ dataSource: AnyObject, maxShares: Int, maxChildren: Int, maxNestedChildren: Int) -> [String: Any] {
    var result: [String: Any] = [
        "focused_summary_available": true,
        "object_class": BBObjectClassName(dataSource),
        "type": String(reflecting: type(of: dataSource)),
        "max_shares": maxShares,
        "max_children": maxChildren,
        "max_nested_children": maxNestedChildren,
        "summary_mode": "compact_provider_manager_datamanager_counts",
    ]

    guard let mediatorValue = BBMirrorChildValue(dataSource, label: "mediator") else {
        result["mediator"] = [
            "present": false,
        ]
        return result
    }

    result["mediator"] = BBCompactFieldSummary(mediatorValue, label: "mediator")

    let providerLabels = [
        "conditionProvider",
        "devicesProvider",
        "etaProvider",
        "locationProvider",
        "peopleProvider",
        "selectionController",
        "productAssetProvider",
        "isRefreshing",
    ]
    var providerSummaries: [String: Any] = [:]
    for providerLabel in providerLabels {
        providerSummaries[providerLabel] = BBCompactFieldSummary(
            BBMirrorChildValue(mediatorValue, label: providerLabel),
            label: providerLabel
        )
    }
    result["providers"] = providerSummaries

    if let devicesProviderValue = BBMirrorChildValue(mediatorValue, label: "devicesProvider"),
       let devicesProvider = BBUnwrappedOptional(devicesProviderValue) {
        let providerFields = [
            "shares",
            "unknownItemsDetectedNearYou",
            "sharingLimits",
            "imageCache",
            "itemImageCache",
            "actionController",
            "isSubscriptionPaused",
            "fmipManager",
        ]
        var fieldSummaries: [String: Any] = [:]
        for field in providerFields {
            let fieldValue = BBMirrorChildValue(devicesProvider, label: field)
            if field == "shares" || field == "unknownItemsDetectedNearYou" {
                fieldSummaries[field] = BBCompactCollectionSummary(
                    fieldValue,
                    label: field,
                    maxElements: min(maxShares, 2),
                    selectedElementFields: [
                        "identifier",
                        "beaconIdentifier",
                        "accessoryIdentifier",
                        "stableIdentifier",
                        "owner",
                        "displayName",
                        "name",
                        "status",
                    ]
                )
            } else {
                fieldSummaries[field] = BBCompactFieldSummary(
                    fieldValue,
                    label: field
                )
            }
        }
        result["devicesProviderFields"] = fieldSummaries

        if let managerValue = BBMirrorChildValue(devicesProvider, label: "fmipManager"),
           let manager = BBUnwrappedOptional(managerValue) {
            let managerFields = [
                "identifier",
                "delegate",
                "siriDelegate",
                "refreshingController",
                "beaconRefreshingController",
                "safeLocationRefreshingController",
                "locationController",
                "dataManager",
                "interactionController",
                "beaconSharingController",
                "isDevicesSnapshotMode",
                "isItemsSnapshotMode",
            ]
            var managerFieldSummaries: [String: Any] = [:]
            for field in managerFields {
                managerFieldSummaries[field] = BBCompactFieldSummary(
                    BBMirrorChildValue(manager, label: field),
                    label: field
                )
            }

            result["fmipManagerFocused"] = [
                "summary": BBCompactFieldSummary(manager, label: "fmipManager"),
                "fields": managerFieldSummaries,
            ]

            if let dataManager = BBMirrorChildValue(manager, label: "dataManager") {
                let deviceFields = [
                    "identifier",
                    "id",
                    "name",
                    "deviceName",
                    "model",
                    "modelName",
                    "rawDeviceModel",
                    "systemVersion",
                    "batteryLevel",
                    "batteryStatus",
                    "location",
                    "lastLocation",
                    "latestLocation",
                    "crowdSourcedLocation",
                    "address",
                    "isOnline",
                    "isOffline",
                ]
                result["dataManagerFocused"] = [
                    "summary": BBCompactFieldSummary(dataManager, label: "dataManager"),
                    "fields": [
                        "devices": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "devices"),
                            label: "devices",
                            maxElements: 2,
                            selectedElementFields: deviceFields
                        ),
                        "crowdSourcedLocations": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "crowdSourcedLocations"),
                            label: "crowdSourcedLocations",
                            maxElements: 2
                        ),
                        "crowdSourcedOriginalLocations": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "crowdSourcedOriginalLocations"),
                            label: "crowdSourcedOriginalLocations",
                            maxElements: 2
                        ),
                        "deviceConnectedStates": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "deviceConnectedStates"),
                            label: "deviceConnectedStates",
                            maxElements: 2
                        ),
                        "safeLocations": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "safeLocations"),
                            label: "safeLocations",
                            maxElements: 2
                        ),
                        "safeLocationsMapping": BBCompactCollectionSummary(
                            BBMirrorChildValue(dataManager, label: "safeLocationsMapping"),
                            label: "safeLocationsMapping",
                            maxElements: 2
                        ),
                    ],
                    "devices_compact": BBFMIPDataManagerDevicesCompact(dataManager, maxDevices: 80),
                    "location_signal": BBCompactLocationSignal(dataManager),
                ]
            } else {
                result["dataManagerFocused"] = [
                    "present": false,
                ]
            }

            if let locationController = BBMirrorChildValue(manager, label: "locationController") {
                result["locationControllerFocused"] = [
                    "summary": BBCompactFieldSummary(locationController, label: "locationController"),
                    "fields": [
                        "currentLocation": BBCompactFieldSummary(BBMirrorChildValue(locationController, label: "currentLocation"), label: "currentLocation"),
                        "limitedPrecision": BBCompactFieldSummary(BBMirrorChildValue(locationController, label: "limitedPrecision"), label: "limitedPrecision"),
                        "locationManager": BBCompactFieldSummary(BBMirrorChildValue(locationController, label: "locationManager"), label: "locationManager"),
                    ],
                    "location_signal": BBCompactLocationSignal(locationController),
                ]
            }

            if let beaconSharingController = BBMirrorChildValue(manager, label: "beaconSharingController") {
                result["beaconSharingControllerFocused"] = [
                    "summary": BBCompactFieldSummary(beaconSharingController, label: "beaconSharingController"),
                    "fields": [
                        "rawShares": BBCompactCollectionSummary(
                            BBMirrorChildValue(beaconSharingController, label: "rawShares"),
                            label: "rawShares",
                            maxElements: 2
                        ),
                        "shares": BBCompactCollectionSummary(
                            BBMirrorChildValue(beaconSharingController, label: "shares"),
                            label: "shares",
                            maxElements: 2
                        ),
                        "isRefreshing": BBCompactFieldSummary(BBMirrorChildValue(beaconSharingController, label: "isRefreshing"), label: "isRefreshing"),
                    ],
                ]
            }
        } else {
            result["fmipManagerFocused"] = [
                "present": false,
            ]
        }
    } else {
        result["devicesProviderFields"] = [
            "present": false,
        ]
        result["fmipManagerFocused"] = [
            "present": false,
        ]
    }

    if let locationProviderValue = BBMirrorChildValue(mediatorValue, label: "locationProvider"),
       let locationProvider = BBUnwrappedOptional(locationProviderValue) {
        let locationProviderFields = [
            "subscriptions",
            "currentLocation",
            "currentHeading",
            "poiLocations",
            "poiFidelity",
            "locationManager",
            "locationShifter",
            "includeHeading",
            "isLocationAuthorized",
            "limitedPrecision",
        ]
        var fieldSummaries: [String: Any] = [:]
        for field in locationProviderFields {
            let fieldValue = BBMirrorChildValue(locationProvider, label: field)
            if field == "subscriptions" || field == "poiLocations" {
                fieldSummaries[field] = BBCompactCollectionSummary(
                    fieldValue,
                    label: field,
                    maxElements: 2
                )
            } else {
                fieldSummaries[field] = BBCompactFieldSummary(
                    fieldValue,
                    label: field
                )
            }
        }
        result["locationProviderFields"] = [
            "fields": fieldSummaries,
            "location_signal": BBCompactLocationSignal(locationProvider),
        ]
    } else {
        result["locationProviderFields"] = [
            "present": false,
        ]
    }

    if let conditionProviderValue = BBMirrorChildValue(mediatorValue, label: "conditionProvider"),
       let conditionProvider = BBUnwrappedOptional(conditionProviderValue) {
        let conditionFields = [
            "areDevicesInitialized",
            "didDevicesFailToInitialize",
            "isNetworkReachable",
            "isAccountInitialized",
            "isAccountSignedIn",
            "isFMIPRestricted",
        ]
        var fieldSummaries: [String: Any] = [:]
        for field in conditionFields {
            fieldSummaries[field] = BBCompactFieldSummary(
                BBMirrorChildValue(conditionProvider, label: field),
                label: field
            )
        }
        result["conditionProviderFields"] = fieldSummaries
    } else {
        result["conditionProviderFields"] = [
            "present": false,
        ]
    }

    return result
}

private func BBDevicesDataManagerDevicesSummary(_ dataSource: AnyObject, maxDevices: Int) -> [String: Any] {
    var result: [String: Any] = [
        "focused_summary_available": true,
        "object_class": BBObjectClassName(dataSource),
        "type": String(reflecting: type(of: dataSource)),
        "max_devices": maxDevices,
        "summary_mode": "app_owned_fmip_datamanager_devices_compact",
    ]

    guard let mediatorValue = BBMirrorChildValue(dataSource, label: "mediator"),
          let mediator = BBUnwrappedOptional(mediatorValue) else {
        result["mediator_present"] = false
        return result
    }

    result["mediator_present"] = true
    result["mediator_type"] = BBMirrorTypeName(mediator)

    if let conditionProviderValue = BBMirrorChildValue(mediator, label: "conditionProvider"),
       let conditionProvider = BBUnwrappedOptional(conditionProviderValue) {
        var conditionFields: [String: Any] = [:]
        for field in ["areDevicesInitialized", "didDevicesFailToInitialize"] {
            if let value = BBCompactScalarLikeValue(BBMirrorChildValue(conditionProvider, label: field)) {
                conditionFields[field] = value
            }
        }
        result["condition_provider"] = conditionFields
    }

    guard let devicesProviderValue = BBMirrorChildValue(mediator, label: "devicesProvider"),
          let devicesProvider = BBUnwrappedOptional(devicesProviderValue) else {
        result["devices_provider_present"] = false
        return result
    }

    result["devices_provider_present"] = true
    result["devices_provider_type"] = BBMirrorTypeName(devicesProvider)
    result["shares"] = BBCollectionCountOnly(BBMirrorChildValue(devicesProvider, label: "shares"), label: "shares")
    result["unknown_items_detected_near_you"] = BBCollectionCountOnly(
        BBMirrorChildValue(devicesProvider, label: "unknownItemsDetectedNearYou"),
        label: "unknownItemsDetectedNearYou"
    )

    guard let managerValue = BBMirrorChildValue(devicesProvider, label: "fmipManager"),
          let manager = BBUnwrappedOptional(managerValue) else {
        result["fmip_manager_present"] = false
        return result
    }

    result["fmip_manager_present"] = true
    result["fmip_manager_type"] = BBMirrorTypeName(manager)

    if let locationController = BBMirrorChildValue(manager, label: "locationController") {
        result["location_controller_current_location"] = BBCompactScalarLikeValue(
            BBMirrorChildValue(locationController, label: "currentLocation")
        ) ?? ["present": false]
    }

    guard let dataManagerValue = BBMirrorChildValue(manager, label: "dataManager"),
          let dataManager = BBUnwrappedOptional(dataManagerValue) else {
        result["data_manager_present"] = false
        return result
    }

    result["data_manager_present"] = true
    result["data_manager_type"] = BBMirrorTypeName(dataManager)
    result["data_manager_counts"] = [
        "devices": BBCollectionCountOnly(BBMirrorChildValue(dataManager, label: "devices"), label: "devices"),
        "safeLocations": BBCollectionCountOnly(BBMirrorChildValue(dataManager, label: "safeLocations"), label: "safeLocations"),
        "crowdSourcedLocations": BBCollectionCountOnly(BBMirrorChildValue(dataManager, label: "crowdSourcedLocations"), label: "crowdSourcedLocations"),
        "crowdSourcedOriginalLocations": BBCollectionCountOnly(BBMirrorChildValue(dataManager, label: "crowdSourcedOriginalLocations"), label: "crowdSourcedOriginalLocations"),
        "deviceConnectedStates": BBCollectionCountOnly(BBMirrorChildValue(dataManager, label: "deviceConnectedStates"), label: "deviceConnectedStates"),
    ]
    result["devices_compact"] = BBFMIPDataManagerDevicesCompact(dataManager, maxDevices: maxDevices)

    return result
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

@_cdecl("BlueBubblesFindMyCopyDevicesDataSourceFocusedSummary")
public func BlueBubblesFindMyCopyDevicesDataSourceFocusedSummary(_ objectPointer: UnsafeMutableRawPointer?, _ maxSections: Int32, _ maxRowsPerSection: Int32, _ maxChildren: Int32, _ maxNestedChildren: Int32) -> UnsafeMutableRawPointer? {
    guard let objectPointer else {
        return Unmanaged.passRetained([
            "focused_summary_available": false,
            "error": "missing object pointer",
        ] as NSDictionary).toOpaque()
    }

    let dataSource = Unmanaged<AnyObject>.fromOpaque(objectPointer).takeUnretainedValue()
    let boundedMaxSections = max(0, min(Int(maxSections), 8))
    let boundedMaxRowsPerSection = max(0, min(Int(maxRowsPerSection), 8))
    let boundedMaxChildren = max(0, min(Int(maxChildren), 64))
    let boundedMaxNestedChildren = max(0, min(Int(maxNestedChildren), 16))
    let summary = BBDevicesDataSourceFocusedSummary(
        dataSource,
        maxSections: boundedMaxSections,
        maxRowsPerSection: boundedMaxRowsPerSection,
        maxChildren: boundedMaxChildren,
        maxNestedChildren: boundedMaxNestedChildren
    )

    return Unmanaged.passRetained(summary as NSDictionary).toOpaque()
}

@_cdecl("BlueBubblesFindMyCopyDevicesProviderFocusedSummary")
public func BlueBubblesFindMyCopyDevicesProviderFocusedSummary(_ objectPointer: UnsafeMutableRawPointer?, _ maxShares: Int32, _ maxChildren: Int32, _ maxNestedChildren: Int32) -> UnsafeMutableRawPointer? {
    guard let objectPointer else {
        return Unmanaged.passRetained([
            "focused_summary_available": false,
            "error": "missing object pointer",
        ] as NSDictionary).toOpaque()
    }

    let dataSource = Unmanaged<AnyObject>.fromOpaque(objectPointer).takeUnretainedValue()
    let boundedMaxShares = max(0, min(Int(maxShares), 8))
    let boundedMaxChildren = max(0, min(Int(maxChildren), 64))
    let boundedMaxNestedChildren = max(0, min(Int(maxNestedChildren), 16))
    let summary = BBDevicesProviderFocusedSummary(
        dataSource,
        maxShares: boundedMaxShares,
        maxChildren: boundedMaxChildren,
        maxNestedChildren: boundedMaxNestedChildren
    )

    return Unmanaged.passRetained(summary as NSDictionary).toOpaque()
}

@_cdecl("BlueBubblesFindMyCopyDevicesDataManagerDevicesSummary")
public func BlueBubblesFindMyCopyDevicesDataManagerDevicesSummary(_ objectPointer: UnsafeMutableRawPointer?, _ maxDevices: Int32) -> UnsafeMutableRawPointer? {
    guard let objectPointer else {
        return Unmanaged.passRetained([
            "focused_summary_available": false,
            "error": "missing object pointer",
        ] as NSDictionary).toOpaque()
    }

    let dataSource = Unmanaged<AnyObject>.fromOpaque(objectPointer).takeUnretainedValue()
    let boundedMaxDevices = max(0, min(Int(maxDevices), 120))
    let summary = BBDevicesDataManagerDevicesSummary(
        dataSource,
        maxDevices: boundedMaxDevices
    )

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
